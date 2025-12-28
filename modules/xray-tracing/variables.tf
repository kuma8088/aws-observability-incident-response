variable "project_prefix" {
  description = "Project prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "default_sampling_rate" {
  description = "Default sampling rate (0.0 to 1.0)"
  type        = number
  default     = 0.2

  validation {
    condition     = var.default_sampling_rate >= 0 && var.default_sampling_rate <= 1
    error_message = "Sampling rate must be between 0.0 and 1.0"
  }
}

variable "error_sampling_rate" {
  description = "Sampling rate for errors (0.0 to 1.0)"
  type        = number
  default     = 1.0

  validation {
    condition     = var.error_sampling_rate >= 0 && var.error_sampling_rate <= 1
    error_message = "Error sampling rate must be between 0.0 and 1.0"
  }
}

variable "reservoir_size" {
  description = "Minimum number of traces to record per second"
  type        = number
  default     = 1

  validation {
    condition     = var.reservoir_size >= 0
    error_message = "Reservoir size must be non-negative"
  }
}
