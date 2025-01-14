Kubernetes AWS Infrastructure - Automation with Terraform
This Terraform project allows you to quickly and easily create a basic infrastructure for Kubernetes clusters on AWS. The code is designed to configure AWS resources suitable for setting up a Kubernetes cluster.
Features
    • VPC and Subnets:
        ◦ 1 private VPC (10.0.0.0/16 CIDR block).
        ◦ 3 public and 3 private subnets.
    • Route Tables:
        ◦ Internet access for public subnets.
        ◦ NAT Gateway routing for private subnets.
    • Security Groups:
        ◦ Required communication permissions between Kubernetes Master and Worker nodes.
        ◦ External access for Worker nodes (e.g., NodePort).
    • Elastic IP and NAT Gateway:
        ◦ Internet access for Worker nodes in private subnets.
    • EC2 Instances:
        ◦ 1 Kubernetes Master node.
        ◦ 2 Worker nodes by default.
    • IAM Roles:
        ◦ IAM role for the Kubernetes Master node with read-only access to S3.
