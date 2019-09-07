# Common-factor module (i.e. abstract base class) for the three types of subnets.
# Note that this module does NOT create a default route, but returns rtb_id so that the subclass can do so.
#
# Copyright (c) 2017 Board of Trustees University of Illinois

terraform {
  required_version = ">= 0.12.9"

  required_providers {
    aws = ">= 2.32"
  }
}

## Inputs

variable "vpc_id" { type = string }
variable "name" { type = string }
variable "cidr_block" { type = string }
variable "availability_zone" { type = string }
variable "pcx_ids" { type = list(string) }
variable "endpoint_ids" { type = list(string) }

# workaround for https://github.com/hashicorp/terraform/issues/4149
variable "endpoint_count" { type = number }

variable map_public_ip_on_launch { type = bool }

# workaround for https://github.com/hashicorp/terraform/issues/11453: have each subclass create its own rtb
#variable propagating_vgws { type = list(string), default = [] }
variable rtb_id { type = string }

# workaround for https://github.com/hashicorp/terraform/issues/10462
variable "dummy_depends_on" {
  type = string
  default = ""
}

variable "tags" {
  description = "Optional custom tags for all taggable resources"
  type        = map
  default     = {}
}

variable "tags_subnet" {
  description = "Optional custom tags for aws_subnet resource"
  type        = map
  default     = {}
}

variable "tags_route_table" {
  description = "Optional custom tags for aws_route_table resource"
  type        = map
  default     = {}
}

#resource "null_resource" "dummy_depends_on" { triggers = { t = var.dummy_depends_on }}

## Outputs

output "id" {
  value = aws_subnet.subnet.id
}

output "route_table_id" {
  #value = aws_route_table.rtb.id
  value = var.rtb_id
}

## Resources

# look up VPC

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

# create Subnet and associated Route Table

resource "aws_subnet" "subnet" {
  tags = merge(var.tags, {
    Name = var.name
  }, var.tags_subnet)

  availability_zone       = var.availability_zone
  cidr_block              = var.cidr_block
  map_public_ip_on_launch = var.map_public_ip_on_launch
  vpc_id                  = var.vpc_id
}

#resource "aws_route_table" "rtb" {
#  tags = merge(var.tags, {
#    Name = "${var.name}-rtb"
#  }, var.tags_route_table)
#
#  vpc_id = var.vpc_id
#  propagating_vgws = var.propagating_vgws
#}

resource "aws_route_table_association" "rtb_assoc" {
  # note: tags not supported
  subnet_id = aws_subnet.subnet.id

  #route_table_id = aws_route_table.rtb.id
  route_table_id = var.rtb_id
}

# routes for VPC Peering Connections (if any)

data "aws_vpc_peering_connection" "pcx" {
  count = length(var.pcx_ids)

  #id = var.pcx_ids[count.index]
  #depends_on = ["null_resource.dummy_depends_on"]

  # As of Terraform 0.9.1, using depends_on here results in rebuilding the
  # aws_route every single run even if nothing has changed.  Work around by
  # embedding the dependency within id instead.
  id = replace(var.pcx_ids[count.index],var.dummy_depends_on,var.dummy_depends_on)
}

resource "aws_route" "pcx" {
  # note: tags not supported
  count = length(var.pcx_ids)

  #route_table_id = aws_route_table.rtb.id
  route_table_id = var.rtb_id

  # pick whichever CIDR block (requester or accepter) isn't _our_ CIDR block
  destination_cidr_block    = replace(data.aws_vpc_peering_connection.pcx[count.index].peer_cidr_block, data.aws_vpc.vpc.cidr_block, data.aws_vpc_peering_connection.pcx[count.index].cidr_block)
  vpc_peering_connection_id = data.aws_vpc_peering_connection.pcx[count.index].id
}

# routes for Gateway VPC Endpoints (if any)

resource "aws_vpc_endpoint_route_table_association" "endpoint_rta" {
  # note: tags not supported
  #count = length(var.endpoint_ids)
  count = var.endpoint_count

  vpc_endpoint_id = var.endpoint_ids[count.index]

  #route_table_id = aws_route_table.rtb.id
  route_table_id = var.rtb_id
}
