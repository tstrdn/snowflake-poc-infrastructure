# Only the core Terraform ruleset. There is no Snowflake tflint plugin, so this
# catches structural problems - unused declarations, missing descriptions,
# naming - rather than provider semantics. Provider correctness is covered by
# `terraform validate` and the speculative plan.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
