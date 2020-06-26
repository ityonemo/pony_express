defmodule PubSubStarter do
  def start_link(who) do
    Enum.each(who, fn name ->
      Supervisor.start_link([{Phoenix.PubSub, [name: name]}],
        strategy: :one_for_one)
    end)
  end
end
