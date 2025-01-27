import Config

if config_env() == :test do
  config :once_more, :sleeper, OnceMore.SendSleeper
end
