terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
  }
}

provider "azurerm" {
  features {}
  skip_provider_registration = true
}

# Retrieve subscription and tenant details for tagging
data "azurerm_client_config" "current" {}

# Resource Group to contain all resources
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
}

# Storage Account for function and general use
resource "azurerm_storage_account" "sa" {
  name                        = var.storage_account_name
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = azurerm_resource_group.rg.location
  account_tier                = "Standard"
  account_replication_type    = "LRS"
  enable_https_traffic_only   = true

  # Enable access time tracking
  blob_properties {
    last_access_time_enabled = true
  }

  tags = var.common_tags
}

# Lifecycle management policy for Storage Account
resource "azurerm_storage_management_policy" "sa_policy" {
  storage_account_id = azurerm_storage_account.sa.id

  rule {
    name    = "default-lifecycle-policy"
    enabled = true

    filters {
      blob_types   = ["blockBlob"]
      prefix_match = [""]
    }

    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than = 30
        delete_after_days_since_modification_greater_than      = 365
      }
    }
  }
}

# App Service Plan (Linux Premium) for Function Apps
resource "azurerm_service_plan" "asp" {
  name                = var.service_plan_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku_name     = var.app_service_sku_name
  os_type      = "Linux"
  worker_count = var.worker_count

  tags = var.common_tags
}

# Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = var.vm_name
  location              = azurerm_resource_group.rg.location
  resource_group_name   = azurerm_resource_group.rg.name
  admin_username        = var.vm_admin_username
  admin_password        = var.vm_admin_password
  size                  = var.vm_size

  network_interface_ids = [var.network_interface_id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  tags = var.common_tags
}

# Linux Function App
resource "azurerm_linux_function_app" "func" {
  name                       = var.function_app_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  service_plan_id            = azurerm_service_plan.asp.id
  storage_account_name       = azurerm_storage_account.sa.name
  storage_account_access_key = azurerm_storage_account.sa.primary_access_key

  site_config {
    # e.g., linux_fx_version = "Python|3.9"
  }

  tags = var.common_tags
}

# Outputs for tracking created resources
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "storage_account_id" {
  description = "ID of the Storage Account"
  value       = azurerm_storage_account.sa.id
}

output "vm_id" {
  description = "ID of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "service_plan_id" {
  description = "ID of the App Service Plan"
  value       = azurerm_service_plan.asp.id
}

output "function_app_hostname" {
  description = "Function App default hostname"
  value       = azurerm_linux_function_app.func.default_hostname
}
