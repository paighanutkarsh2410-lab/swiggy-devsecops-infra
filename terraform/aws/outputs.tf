output "server_public_ip" {
  description = "Public IP address of the K3s server."
  value       = aws_instance.server.public_ip
}

output "ssh_command" {
  description = "Command to log in to the server."
  value       = "ssh ec2-user@${aws_instance.server.public_ip}"
}

output "website_url" {
  description = "Website address once the app is deployed."
  value       = "http://${aws_instance.server.public_ip}"
}
