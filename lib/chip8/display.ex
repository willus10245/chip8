defmodule Chip8.Display do
  def new do
    for x <- 0..63, y <- 0..31, into: %{} do
      {{x, y}, 0}
    end
  end
end
