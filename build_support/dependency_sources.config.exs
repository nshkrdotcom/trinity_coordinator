%{
  deps: %{
    agent_session_manager: %{
      path: "../agent_session_manager",
      github: %{repo: "nshkrdotcom/agent_session_manager", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    gemini_cli_sdk: %{
      path: "../gemini_cli_sdk",
      github: %{repo: "nshkrdotcom/gemini_cli_sdk", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    inference: %{
      path: "../inference/apps/inference",
      github: %{repo: "nshkrdotcom/inference", branch: "main", subdir: "apps/inference"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_safetensors: %{
      path: "../../North-Shore-AI/crucible_safetensors",
      github: %{repo: "North-Shore-AI/crucible_safetensors", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_factorization: %{
      path: "../../North-Shore-AI/crucible_factorization",
      github: %{repo: "North-Shore-AI/crucible_factorization", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_tensor_patch: %{
      path: "../../North-Shore-AI/crucible_tensor_patch",
      github: %{repo: "North-Shore-AI/crucible_tensor_patch", branch: "main"},
      hex: "~> 0.1.0",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    },
    crucible_model_registry: %{
      path: "../../North-Shore-AI/crucible_model_registry",
      github: %{repo: "North-Shore-AI/crucible_model_registry", branch: "main"},
      hex: "~> 0.3.1",
      default_order: [:path, :github, :hex],
      publish_order: [:hex]
    }
  }
}
