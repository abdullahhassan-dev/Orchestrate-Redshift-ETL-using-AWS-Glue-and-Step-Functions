data "aws_route_tables" "default_vpc" {
  vpc_id = data.aws_vpc.default.id
}

# S3 gateway endpoint (free): Glue job ko S3 tak raasta deta hai
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = data.aws_vpc.default.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.default_vpc.ids
}

# Secrets Manager interface endpoint: Glue job ko password padhne ka raasta deta hai
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [data.aws_subnet.glue_subnet.id]
  security_group_ids  = [aws_security_group.redshift_sg.id]
  private_dns_enabled = true
}