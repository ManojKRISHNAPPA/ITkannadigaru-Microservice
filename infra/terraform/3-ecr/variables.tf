variable "project" {
  type    = string
  default = "deployecho"
}

variable "repositories" {
  type    = list(string)
  default = ["deployecho-backend", "deployecho-frontend"]
}
