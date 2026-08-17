# ── Dados dinâmicos ───────────────────────────────────────────────────────────

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.project_name}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, 2)

  public_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]
}

# ── VPC ───────────────────────────────────────────────────────────────────────
# Recurso: aws_vpc
# Rede isolada onde todos os componentes residem.
# DNS habilitado para que pods resolvam serviços por nome.

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name}-vpc"
    # Tags necessárias para o EKS descobrir subnets automaticamente
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
}

# ── Subnets Públicas ──────────────────────────────────────────────────────────
# Recurso: aws_subnet (public)
# Hospeda: Internet-facing Load Balancers (ALB/NLB)
# Cada subnet em uma AZ diferente para alta disponibilidade.

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${local.name}-public-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"  # Indica ao EKS para criar LBs públicos aqui
    "kubernetes.io/cluster/${local.name}" = "shared"
  }
}

# ── Subnets Privadas ──────────────────────────────────────────────────────────
# Recurso: aws_subnet (private)
# Hospeda: EKS worker nodes e RDS PostgreSQL
# Sem IP público — saída via NAT Gateway.

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.private_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name                              = "${local.name}-private-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"  # Para LBs internos
    "kubernetes.io/cluster/${local.name}"    = "shared"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
# Recurso: aws_internet_gateway
# Porta de saída/entrada para as subnets PÚBLICAS.

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name}-igw"
  }
}

# ── Elastic IP para o NAT Gateway ─────────────────────────────────────────────
# Recurso: aws_eip
# IP fixo associado ao NAT Gateway.

resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name}-nat-eip"
  }
}

# ── NAT Gateway ───────────────────────────────────────────────────────────────
# Recurso: aws_nat_gateway
# Permite que os nodes nas subnets privadas acessem a internet (pull de imagens,
# atualizações) sem ficarem expostos publicamente.
# Um único NAT reduz custo (dev); em prod use um por AZ.

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id  # NAT fica em subnet pública

  tags = {
    Name = "${local.name}-nat"
  }
}

# ── Route Table — Pública ─────────────────────────────────────────────────────
# Recurso: aws_route_table (public)
# Todo tráfego externo (0.0.0.0/0) vai direto ao Internet Gateway.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name}-public-rt"
  }
}

# ── Route Table — Privada ─────────────────────────────────────────────────────
# Recurso: aws_route_table (private)
# Tráfego externo sai pelo NAT Gateway (sem expor IP dos nodes).

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${local.name}-private-rt"
  }
}

# ── Associações ───────────────────────────────────────────────────────────────
# Recurso: aws_route_table_association
# Liga cada subnet à sua route table correspondente.

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
