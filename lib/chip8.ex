defmodule Chip8 do
  use GenServer
  import Bitwise

  require Logger

  alias __MODULE__.{Display, Memory, Rom, State}

  @renderer Application.compile_env(:chip8, :renderer)
  @tick_interval 5

  def start_link(path) do
    GenServer.start_link(__MODULE__, [path])
  end

  def init(path) do
    memory =
      path
      |> Rom.load_to_memory(Memory.new())

    state = State.new()

    tick()

    {:ok, %{state | memory: memory, renderer: @renderer}}
  end

  def handle_info(:tick, %{pc: pc, memory: memory} = state) do
    opcode = opcode(memory[pc], memory[pc + 1])
    Logger.debug("DECODED OPCODE: " <> opcode)

    new_state =
      %{state | pc: pc + 2}
      |> execute(opcode)

    if new_state.draw? do
      new_state.renderer.render(new_state.display)
    end

    tick()

    {:noreply, %{new_state | draw?: false}}
  end

  def execute(state, "00E0") do
    %{state | display: Display.new(), draw?: true}
  end

  def execute(state, <<"1", n1, n2, n3>>) do
    new_pc = parse_hex(<<n1, n2, n3>>)
    %{state | pc: new_pc}
  end

  def execute(state, <<"3", x, n1, n2>>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    val = parse_hex(<<n1, n2>>)
    
    if state[vX] == val do
      %{state | pc: state.pc + 2}
    else
      state
    end
  end

  def execute(state, <<"4", x, n1, n2>>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    val = parse_hex(<<n1, n2>>)
    
    if state[vX] != val do
      %{state | pc: state.pc + 2}
    else
      state
    end
  end

  def execute(state, <<"6", x, n1, n2>>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    val = parse_hex(<<n1, n2>>)

    Map.put(state, vX, val)
  end

  def execute(state, <<"7", x, n1, n2>>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    val = parse_hex(<<n1, n2>>)

    Map.update!(state, vX, &(rem(&1 + val, 256)))
  end

  def execute(state, <<"A", n1, n2, n3>>) do
    new_i = parse_hex(<<n1, n2, n3>>)
    %{state | i: new_i}
  end

  def execute(state, <<"D", x, y, n>>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    start_x = state[vX] &&& 63
    start_y = state[vY] &&& 31
    n = parse_hex(<<n>>)
    
    {new_display, new_vf} = 
      Enum.reduce_while(0..n-1, {state.display, 0}, fn y, {disp, vf} ->
        if start_y + y == 32 do
          {:halt, {disp, vf}}
        else
          result =
            state.memory[state.i + y]
            |> to_digits()
            |> Enum.with_index()
            |> Enum.reduce_while({disp, vf}, fn {bit, x}, {disp, vf} ->
              if start_x + x == 64 do
                {:halt, {disp, vf}}
              else
                coord = {start_x + x, start_y + y}
                new_vf = vf ||| (bit &&& disp[coord])

                new_disp = update_in(disp, [coord], fn pix ->
                  bxor(pix, bit)
                end)

                {:cont, {new_disp, new_vf}}
              end
            end)
          

          {:cont, result}
        end
      end)

    %{state | display: new_display, vF: new_vf, draw?: true}
  end

  def opcode(byte1, byte2) do
    (byte1 <<< 8 ||| byte2)
    |> Integer.to_string(16)
    |> String.pad_leading(4, "0")
  end

  defp parse_hex(binary) do
    {result, _} = Integer.parse(binary, 16)
    result
  end

  def render(display) do
    pixels = for y <- 0..31, x <- 0..63, do: display[{x, y}]
    
    pixels
    |> Enum.map(fn 
      0 -> " "
      1 -> "X"
    end)
    |> Enum.chunk_every(64)
    |> Enum.map(&Enum.join/1)
    |> Enum.join("\n")
    |> IO.puts
  end

  defp tick() do
    Process.send_after(self(), :tick, @tick_interval)
  end

  defp to_digits(byte) do
    digits = Integer.digits(byte, 2)
    padding = List.duplicate(0, 8 - length(digits))
    
    padding ++ digits
  end
end
