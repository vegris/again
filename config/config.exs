import Config

if config_env() == :test do
  config :again, :sleeper, Again.SendSleeper
end
