import Config

if Mix.env() == :test do
  config :pony_express, :use_multiverses, true
end
