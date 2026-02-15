data "aws_caller_identity" "current" {}

locals {
  tags = {
    Project = var.project
  }
}

resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repositories)

  name                 = each.value
  image_tag_mutability = "MUTABLE" # We'll use tags like dev-<sha>, prod-<sha>
  force_delete         = true      # For learning; prod often false + controlled cleanup

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.tags, { Name = each.value })
}
