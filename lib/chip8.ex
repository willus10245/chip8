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

  def execute(state, "00EE") do
    [new_pc | rest_stack] = state.stack
    %{state | pc: new_pc, stack: rest_stack}
  end

  def execute(state, <<"1", n1, n2, n3>>) do
    new_pc = parse_hex(<<n1, n2, n3>>)
    %{state | pc: new_pc}
  end

  def execute(state, <<"2", n1, n2, n3>>) do
    new_pc = parse_hex(<<n1, n2, n3>>)
    old_pc = state.pc
    %{state | pc: new_pc, stack: [old_pc | state.stack]}
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

  def execute(state, <<"5", x, y, "0">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)

    if state[vX] == state[vY] do
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

  def execute(state, <<"8", x, y, "0">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    
    Map.put(state, vX, state[vY])
  end

  def execute(state, <<"8", x, y, "1">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    
    Map.put(state, vX, state[vX] ||| state[vY])
  end

  def execute(state, <<"8", x, y, "2">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    
    Map.put(state, vX, state[vX] &&& state[vY])
  end

  def execute(state, <<"8", x, y, "3">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    
    Map.put(state, vX, bxor(state[vX], state[vY]))
  end

  def execute(state, <<"8", x, y, "4">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    sum = state[vX] + state[vY]
    vF = div(sum, 256)
    sum = rem(sum, 256)

    state
    |> Map.put(vX, sum)
    |> Map.put(:vF, vF)
  end

  def execute(state, <<"8", x, y, "5">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    diff = state[vX] - state[vY]
    vF = if diff >= 0, do: 1, else: 0
    diff = if diff >= 0, do: diff, else: diff + 256

    state
    |> Map.put(vX, diff)
    |> Map.put(:vF, vF)
  end

  def execute(state, <<"8", x, y, "7">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)
    diff = state[vY] - state[vX]
    vF = if diff >= 0, do: 1, else: 0
    diff = if diff >= 0, do: diff, else: diff + 256

    state
    |> Map.put(vX, diff)
    |> Map.put(:vF, vF)
  end

  def execute(state, <<"9", x, y, "0">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    vY = String.to_existing_atom("v" <> <<y>>)

    if state[vX] != state[vY] do
      %{state | pc: state.pc + 2}
    else
      state
    end
  end

  def execute(state, <<"A", n1, n2, n3>>) do
    new_i = parse_hex(<<n1, n2, n3>>)
    %{state | i: new_i}
  end

  def execute(state, <<"B", n1, n2, n3>>) do
    val = parse_hex(<<n1, n2, n3>>)
    %{state | pc: val + state.v0}
  end

  def execute(state, <<"C", x, n1, n2>>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    val = parse_hex(<<n1, n2>>)
    rand_n = :rand.uniform(0xFFFF)
    
    Map.put(state, vX, rand_n &&& val)
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

  def execute(state, <<"F", x, "07">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    
    Map.put(state, vX, state.delay_timer)
  end

  def execute(state, <<"F", x, "15">>) do
    vX = String.to_existing_atom("v" <> <<x>>)

    %{state | delay_timer: state[vX]}
  end

  def execute(state, <<"F", x, "18">>) do
    vX = String.to_existing_atom("v" <> <<x>>)

    %{state | sound_timer: state[vX]}
  end

  def execute(state, <<"F", x, "1E">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    val = state[vX]

    new_i = state.i + val

    new_vf = if new_i > 0xFFF, do: 1, else: 0

    %{state | i: new_i, vF: new_vf}
  end

  def execute(state, <<"F", x, "29">>) do
    vX = String.to_existing_atom("v" <> <<x>>)
    %{state | i: state[vX] * 5}
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
