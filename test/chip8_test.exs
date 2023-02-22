defmodule Chip8Test do
  use ExUnit.Case
  doctest Chip8

  alias Chip8.{Display, Memory, Rom, State}

  import Chip8

  test "runs" do
    rom_path = Path.expand("../roms/ibm.ch8", __DIR__)
    {:ok, pid} = Chip8.start_link(rom_path)

    assert Process.alive?(pid)
  end

  test "loading ROMs" do
    path = Path.expand("../roms/ibm.ch8", __DIR__)

    [byte1, byte2 | _] = Rom.load(path)

    assert "00E0" = opcode(byte1, byte2)
  end

  test "00E0 clears screen" do
    display = 
      Display.new()
      |> Map.put({1, 1}, 1) 
    state = %State{display: display}

    %{display: new_display} = execute(state, "00E0")

    assert new_display == Display.new()
  end

  test "00EE returns to pc on top of stack" do
    state = %State{pc: 0x555, stack: [0x200]}

    assert %{pc: 0x200, stack: []} = execute(state, "00EE")
  end

  test "1NNN sets the program count" do
    state = %State{pc: 0}

    assert %{pc: 5} = execute(state, "1005")
  end

  test "2NNN sets program count and puts old pc on stack" do
    state = %State{pc: 0x200, stack: []}

    assert %{pc: 0x311, stack: [0x200]}
      = execute(state, "2311")
  end

  test "3XNN skips if vX == NN" do
    state = %State{pc: 0x200, v0: 0x0A}

    assert %{pc: 0x202} = execute(state, "300A")
  end

  test "3XNN doesn't skip if vX != NN" do
    state = %State{pc: 0x200, v0: 0x0B}

    assert %{pc: 0x200} = execute(state, "300A")
  end

  test "4XNN skips if vX != NN" do
    state = %State{pc: 0x200, v0: 0x0B}

    assert %{pc: 0x202} = execute(state, "400A")
  end

  test "4XNN doesn't skip if vX == NN" do
    state = %State{pc: 0x200, v0: 0x0A}

    assert %{pc: 0x200} = execute(state, "400A")
  end

  test "5XY0 skips if vX == vY" do
    state = %State{pc: 0x200, v0: 0xDD, v1: 0xDD}

    assert %{pc: 0x202} = execute(state, "5010")
  end

  test "5XY0 doesn't skip if vX != vY" do
    state = %State{pc: 0x200, v0: 0xDE, v1: 0xDD}

    assert %{pc: 0x200} = execute(state, "5010")
  end

  test "6XNN sets a register" do
    state = State.new()

    assert %{v2: 31} = execute(state, "621F")
  end

  test "7XNN adds to a register" do
    state = State.new() |> Map.put(:v3, 1)

    assert %{v3: 32} = execute(state, "731F")
  end

  test "7XNN handles overflow and doesn't set carry flag" do
    state = State.new() |> Map.put(:v3, 255)

    assert %{v3: 0, vF: 0} = execute(state, "7301")
  end

  test "8XY0 sets vX to value of vY" do
    state = %State{v0: 0, v1: 1}

    assert %{v0: 1} = execute(state, "8010")
  end

  test "8XY1 sets vX to value of vX | vY" do
    state = %State{v3: 0x10, v4: 0xA3}

    assert %{v3: 0xB3} = execute(state, "8341")
  end

  test "8XY2 sets vX to value of vX & vY" do
    state = %State{v3: 0x13, v4: 0x1A}

    assert %{v3: 0x12} = execute(state, "8342")
  end

  test "8XY3 sets vX to value of vX XOR vY" do
    state = %State{v5: 0x13, v6: 0x1A}

    assert %{v5: 0x9} = execute(state, "8563")
  end

  test "8XY4 sets vX to vX + vY" do
    state = %State{v7: 0xA, v8: 0xA}

    assert %{v7: 0x14, vF: 0} = execute(state, "8784")
  end

  test "8XY4 handles overflow" do
    state = %State{v7: 0xFF, v8: 0xA}

    assert %{v7: 0x9, vF: 1} = execute(state, "8784")
  end

  test "8XY5 sets vX to vX - vY" do
    state = %State{v7: 0xA, v8: 0x6}

    assert %{v7: 0x4, vF: 1} = execute(state, "8785")
  end

  test "8XY5 handles underflow" do
    state = %State{v7: 0xA, v8: 0x6}

    assert %{v8: 0xFC, vF: 0} = execute(state, "8875")
  end

  test "8XY7 sets vX to vX - vY" do
    state = %State{v7: 0x6, v8: 0xA}

    assert %{v7: 0x4, vF: 1} = execute(state, "8787")
  end

  test "9XY0 skips if vX != vY" do  
    state = %State{pc: 0x200, v0: 0xDE, v1: 0xDD}

    assert %{pc: 0x202} = execute(state, "9010")
  end

  test "9XY0 doesn't skip if vX != vY" do  
    state = %State{pc: 0x200, v0: 0xDD, v1: 0xDD}

    assert %{pc: 0x200} = execute(state, "9010")
  end

  test "ANNN sets index register" do
    state = State.new()

    assert %{i: 4} = execute(state, "A004")
  end

  describe "Dxyn: Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision" do
    test "display '0' sprite at (0, 0)" do
      state = %State{i: 0x0, v0: 0, v1: 0, vF: 0, display: Display.new(), memory: Memory.new()}

      %{display: display, vF: vF} = execute(state, "D015")

      assert display[{0, 0}] == 1
      assert display[{1, 0}] == 1
      assert display[{2, 0}] == 1
      assert display[{3, 0}] == 1
      assert display[{4, 0}] == 0

      assert display[{0, 1}] == 1
      assert display[{1, 1}] == 0
      assert display[{2, 1}] == 0
      assert display[{3, 1}] == 1
      assert display[{4, 1}] == 0

      assert display[{0, 2}] == 1
      assert display[{1, 2}] == 0
      assert display[{2, 2}] == 0
      assert display[{3, 2}] == 1
      assert display[{4, 2}] == 0

      assert display[{0, 3}] == 1
      assert display[{1, 3}] == 0
      assert display[{2, 3}] == 0
      assert display[{3, 3}] == 1
      assert display[{4, 3}] == 0

      assert display[{0, 4}] == 1
      assert display[{1, 4}] == 1
      assert display[{2, 4}] == 1
      assert display[{3, 4}] == 1
      assert display[{4, 4}] == 0

      assert vF == 0
    end

    test "display '1' sprite at (0, 0)" do
      state = %State{i: 0x5, v0: 0, v1: 0, vF: 0, display: Display.new(), memory: Memory.new()}

      %{display: display, vF: vF} = execute(state, "D015")

      assert display[{0, 0}] == 0
      assert display[{1, 0}] == 0
      assert display[{2, 0}] == 1
      assert display[{3, 0}] == 0
      assert display[{4, 0}] == 0

      assert display[{0, 1}] == 0
      assert display[{1, 1}] == 1
      assert display[{2, 1}] == 1
      assert display[{3, 1}] == 0
      assert display[{4, 1}] == 0

      assert display[{0, 2}] == 0
      assert display[{1, 2}] == 0
      assert display[{2, 2}] == 1
      assert display[{3, 2}] == 0
      assert display[{4, 2}] == 0

      assert display[{0, 3}] == 0
      assert display[{1, 3}] == 0
      assert display[{2, 3}] == 1
      assert display[{3, 3}] == 0
      assert display[{4, 3}] == 0

      assert display[{0, 4}] == 0
      assert display[{1, 4}] == 1
      assert display[{2, 4}] == 1
      assert display[{3, 4}] == 1
      assert display[{4, 4}] == 0

      assert vF == 0
    end

    test "collision: display 0 then 1" do
      state = %State{v0: 0, v1: 0, vF: 0, display: Display.new(), memory: Memory.new()}
      # Set I to point to '0' sprite
      # Draw '0' sprite
      # Set I to point to '1' sprite
      # Draw '1' sprite
      new_state =
        state
        |> execute("A000")
        |> execute("D015")
        |> execute("A005")
        |> execute("D015")

      assert new_state.vF == 1
    end
  end
end
