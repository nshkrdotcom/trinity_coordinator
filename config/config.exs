import Config

config :exla,
  clients: [
    cuda: [platform: :cuda, preallocate: false, memory_fraction: 0.35],
    rocm: [platform: :rocm, preallocate: false, memory_fraction: 0.35],
    host: [platform: :host]
  ],
  preferred_clients: [:cuda, :host]

env_config = Path.expand("#{config_env()}.exs", __DIR__)

if File.exists?(env_config) do
  import_config "#{config_env()}.exs"
end
