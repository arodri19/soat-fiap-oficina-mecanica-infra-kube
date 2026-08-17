locals {
  name = "${var.project_name}-${var.environment}"
}

# ── IAM: Role do Control Plane ────────────────────────────────────────────────
# Recurso: aws_iam_role (cluster)
# O EKS precisa de permissões para gerenciar recursos AWS em nome do cluster
# (ex: criar ENIs, comunicar com EC2 e ELB).

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${local.name}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

# Recurso: aws_iam_role_policy_attachment (cluster)
# AmazonEKSClusterPolicy: permite ao control plane chamar APIs da AWS.
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── IAM: Role dos Worker Nodes ────────────────────────────────────────────────
# Recurso: aws_iam_role (node)
# As instâncias EC2 dos nodes precisam se comunicar com a API do EKS,
# fazer pull de imagens no ECR e usar o CNI de rede.

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.name}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
}

# Recurso: aws_iam_role_policy_attachment (node — 3 políticas)
# AmazonEKSWorkerNodePolicy  : permite ao node se registrar no cluster
# AmazonEKS_CNI_Policy       : permite ao VPC CNI gerenciar IPs dos pods
# AmazonEC2ContainerRegistryReadOnly: permite pull de imagens no ECR

resource "aws_iam_role_policy_attachment" "eks_worker_node" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── Security Group: Control Plane ─────────────────────────────────────────────
# Recurso: aws_security_group (cluster)
# Controla o tráfego de entrada/saída da API do Kubernetes.
# Nodes precisam alcançar o control plane na porta 443 (HTTPS).

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name}-eks-cluster-sg"
  description = "Security group do control plane EKS"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTPS dos worker nodes para a API"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-eks-cluster-sg"
  }
}

# ── Security Group: Worker Nodes ──────────────────────────────────────────────
# Recurso: aws_security_group (nodes)
# Permite comunicação entre pods (self), controle do cluster e egresso livre.

resource "aws_security_group" "eks_nodes" {
  name        = "${local.name}-eks-nodes-sg"
  description = "Security group dos worker nodes EKS"
  vpc_id      = var.vpc_id

  ingress {
    description = "Pod-to-pod communication within the node group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-eks-nodes-sg"
    # Tag obrigatória para o Cluster Autoscaler descobrir o node group
    "kubernetes.io/cluster/${local.name}" = "owned"
  }
}

# Regra separada para evitar referência circular entre os dois SGs
resource "aws_security_group_rule" "nodes_from_cluster" {
  description              = "Control plane para nodes (kubelet, webhook)"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
# Recurso: aws_eks_cluster
# Control plane gerenciado pela AWS. Nodes ficam em subnets privadas.
# endpoint_public_access = true permite acesso via kubectl de fora do cluster.
# Em produção, considere false + VPN/bastion.

resource "aws_eks_cluster" "main" {
  name     = local.name
  version  = var.cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = {
    Name = "${local.name}-cluster"
  }
}

# ── EKS Managed Node Group ────────────────────────────────────────────────────
# Recurso: aws_eks_node_group
# AWS gerencia o ciclo de vida dos nodes (provisionamento, atualizações, drain).
# scaling_config integra com o Cluster Autoscaler ou Karpenter.

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-nodes"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = [var.node_instance_type]
  ami_type       = "AL2023_x86_64_STANDARD" # Amazon Linux 2023 (AL2 é descontinuado em 26/11/2025)
  capacity_type  = "ON_DEMAND"              # SPOT reduz custo em 60-70% com menos garantia

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Substitui 1 node por vez durante atualizações (zero downtime)
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.ecr_read,
  ]

  tags = {
    Name = "${local.name}-node-group"
  }
}
