

output "private_subnets_ids" {
    value = [ for subnet in module.private-facing-subnet: subnet.id ]
}

output "public_subnets_ids" {
    value = [ for subnet in module.public-facing-subnet: subnet.id ]
}

output "campus_subnets_ids" {
    value = [ for subnet in module.campus-facing-subnet: subnet.id ]
}