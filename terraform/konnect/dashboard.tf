locals {
  konnect_ui_region = replace(replace(var.konnect_server_url, "https://", ""), ".api.konghq.com", "")
}

resource "konnect_dashboard" "azure_obo_demo" {
  provider = konnect-beta

  name = var.dashboard_name

  labels = {
    owner   = "picketfence-labs"
    purpose = "azure-obo-demo"
  }

  definition = {
    preset_filters = [
      {
        field    = "control_plane"
        operator = "in"
        value    = jsonencode([konnect_gateway_control_plane.azure_obo_demo.id])
      }
    ]

    tiles = [
      # API usage: the three Gateway routes identify browser/API, MCP, and LLM traffic.
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 0 }
            size     = { cols = 2, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "API / MCP / LLM calls by route"
                  stacked     = false
                }
              }
              query = {
                api_usage = {
                  datasource  = "api_usage"
                  metrics     = ["request_count"]
                  dimensions  = ["time", "route"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 2, row = 0 }
            size     = { cols = 2, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "P95 response latency by route"
                  stacked     = false
                }
              }
              query = {
                api_usage = {
                  datasource  = "api_usage"
                  metrics     = ["response_latency_p95"]
                  dimensions  = ["time", "route"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 4, row = 0 }
            size     = { cols = 2, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "Error rate by route"
                  stacked     = false
                }
              }
              query = {
                api_usage = {
                  datasource  = "api_usage"
                  metrics     = ["error_rate"]
                  dimensions  = ["route", "time"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 2 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "Calls by client identity and route"
                }
              }
              query = {
                api_usage = {
                  datasource = "api_usage"
                  metrics    = ["request_count"]
                  dimensions = ["route", "principal"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 3, row = 2 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "Gateway / upstream latency breakdown"
                  stacked     = false
                }
              }
              query = {
                api_usage = {
                  datasource = "api_usage"
                  metrics = [
                    "response_latency_p95",
                    "upstream_latency_p95",
                    "kong_internal_latency_p95",
                  ]
                  dimensions  = ["time"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },

      # Agentic usage: AI MCP Proxy emits MCP method, tool, error, and latency dimensions.
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 4 }
            size     = { cols = 2, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "MCP calls by tool"
                  stacked     = false
                }
              }
              query = {
                agentic_usage = {
                  datasource  = "agentic_usage"
                  metrics     = ["request_count"]
                  dimensions  = ["time", "mcp_tool_name"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 2, row = 4 }
            size     = { cols = 2, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "MCP P95 response latency by tool"
                  stacked     = false
                }
              }
              query = {
                agentic_usage = {
                  datasource  = "agentic_usage"
                  metrics     = ["response_latency_p95"]
                  dimensions  = ["time", "mcp_tool_name"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 4, row = 4 }
            size     = { cols = 2, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "MCP error rate by tool"
                  stacked     = false
                }
              }
              query = {
                agentic_usage = {
                  datasource  = "agentic_usage"
                  metrics     = ["error_rate"]
                  dimensions  = ["time", "mcp_tool_name"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 6 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "MCP calls by client identity"
                }
              }
              query = {
                agentic_usage = {
                  datasource = "agentic_usage"
                  metrics    = ["request_count"]
                  dimensions = ["principal", "mcp_method"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 3, row = 6 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "MCP calls by method and tool"
                }
              }
              query = {
                agentic_usage = {
                  datasource = "agentic_usage"
                  metrics    = ["request_count"]
                  dimensions = ["mcp_method", "mcp_tool_name"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },

      # LLM usage summary.
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 8 }
            size     = { cols = 1, rows = 1 }
          }
          definition = {
            chart_visualization = {
              chart = {
                single_value = {
                  type           = "single_value"
                  chart_title    = "LLM calls"
                  decimal_points = 0
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["ai_request_count"]
                  dimensions = []
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 1, row = 8 }
            size     = { cols = 1, rows = 1 }
          }
          definition = {
            chart_visualization = {
              chart = {
                single_value = {
                  type           = "single_value"
                  chart_title    = "LLM latency avg"
                  decimal_points = 2
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["llm_latency_average"]
                  dimensions = []
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 2, row = 8 }
            size     = { cols = 1, rows = 1 }
          }
          definition = {
            chart_visualization = {
              chart = {
                single_value = {
                  type           = "single_value"
                  chart_title    = "LLM error rate"
                  decimal_points = 2
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["error_rate"]
                  dimensions = []
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 3, row = 8 }
            size     = { cols = 1, rows = 1 }
          }
          definition = {
            chart_visualization = {
              chart = {
                single_value = {
                  type           = "single_value"
                  chart_title    = "Total tokens"
                  decimal_points = 0
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["total_tokens"]
                  dimensions = []
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 4, row = 8 }
            size     = { cols = 1, rows = 1 }
          }
          definition = {
            chart_visualization = {
              chart = {
                single_value = {
                  type           = "single_value"
                  chart_title    = "Prompt tokens"
                  decimal_points = 0
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["prompt_tokens"]
                  dimensions = []
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 5, row = 8 }
            size     = { cols = 1, rows = 1 }
          }
          definition = {
            chart_visualization = {
              chart = {
                single_value = {
                  type           = "single_value"
                  chart_title    = "Completion tokens"
                  decimal_points = 0
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["completion_tokens"]
                  dimensions = []
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },

      # LLM breakdowns by model/provider and authenticated client dimensions.
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 9 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "LLM calls by response model"
                  stacked     = false
                }
              }
              query = {
                llm_usage = {
                  datasource  = "llm_usage"
                  metrics     = ["ai_request_count"]
                  dimensions  = ["time", "ai_response_model"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 3, row = 9 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "Total tokens by model and provider"
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["total_tokens"]
                  dimensions = ["ai_response_model", "ai_provider"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 11 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "LLM calls by client identity"
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["ai_request_count"]
                  dimensions = ["principal", "application"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 3, row = 11 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "Total tokens by client identity"
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["total_tokens"]
                  dimensions = ["principal", "application"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 0, row = 13 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                timeseries_line = {
                  type        = "timeseries_line"
                  chart_title = "Token usage over time by model"
                  stacked     = false
                }
              }
              query = {
                llm_usage = {
                  datasource  = "llm_usage"
                  metrics     = ["total_tokens"]
                  dimensions  = ["time", "ai_response_model"]
                  filters     = []
                  granularity = "fiveMinutely"
                  limit       = 50
                }
              }
            }
          }
        }
      },
      {
        chart = {
          type = "chart"
          layout = {
            position = { col = 3, row = 13 }
            size     = { cols = 3, rows = 2 }
          }
          definition = {
            chart_visualization = {
              chart = {
                top_n = {
                  type        = "top_n"
                  chart_title = "LLM cost by model and provider"
                }
              }
              query = {
                llm_usage = {
                  datasource = "llm_usage"
                  metrics    = ["cost"]
                  dimensions = ["ai_response_model", "ai_provider"]
                  filters    = []
                  limit      = 50
                }
              }
            }
          }
        }
      },
    ]
  }
}
