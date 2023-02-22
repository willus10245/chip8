defmodule Chip8.Rom do
  def load_to_memory(path, memory) do
    path
    |> load()
    |> do_load_to_memory(memory, 0x200)
  end

  def load(path) do
    {:ok, rom} = File.read(path)

    to_bytes(rom, [])
  end

  defp do_load_to_memory([], memory, _) do
    memory
  end

  defp do_load_to_memory([byte | rest], memory, addr) do
    do_load_to_memory(rest, Map.put(memory, addr, byte), addr + 1)
  end

  defp to_bytes(<<>>, bytes) do
    Enum.reverse(bytes)
  end

  defp to_bytes(<<byte::size(8), rest::binary>>, bytes) do
    to_bytes(rest, [byte | bytes])
  end
end
