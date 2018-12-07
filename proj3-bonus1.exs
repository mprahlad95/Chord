
# The input provided will be of the form:
# proj3.exs numNodes numRequests
# Where numNodes is the number of peers to be created in the peer to peer
# system and numRequests the number of requests each peer has to make. When
# all peers performed that many requests, the program can exit. Each peer should
# send a request/second.
# Output: Print the average number of hops (node connections) that have to
# be traversed to deliever a message.

defmodule ChordRing do
  use DynamicSupervisor

  @m 4
  @maxNumNodes :math.pow(2, @m) |> round

  defp parse_inputs do
    command_line_args = System.argv()
    if length(command_line_args) < 2 do
      raise ArgumentError, message: "there must be at least three arguments: numNodes, topology, algorithm"
    end
    [numNodes, numRequests | _tail] = command_line_args

    numNodes =
      try do
        numNodes |> String.trim_trailing |> String.to_integer
      rescue
        ArgumentError -> IO.puts("numNodes must be an integer. Defaulting #{numNodes} to 1")
        1
      end

    numRequests =
      try do
        numRequests |> String.trim_trailing |> String.to_integer
      rescue
        ArgumentError -> IO.puts("numRequests must be an integer. Defaulting #{numRequests} to 1")
        1
      end
    [numNodes, numRequests]
  end

  def main do
    [numNodes, numRequests] = parse_inputs()

    # IO.puts "numNodes = #{numNodes} and numRquests = #{numRequests}"

    # Identifiers are ordered on an identifier circle modulo 2 to the power m
    maxNumNodes = :math.pow(2, @m) |> round #1048576

    {:ok, super_pid} = start_link()

    {:ok, existing_node_pid} = add_node(0)
    node_id_map = Map.put(%{}, 0, existing_node_pid)
    set_finger_tables_in_children(node_id_map) #build finger table for 0
    store_messages_in_children(node_id_map, numNodes*3) # add all the messaages in node 0
    GenServer.call(existing_node_pid, {:set_succ, existing_node_pid})
    GenServer.call(existing_node_pid, {:set_pred, existing_node_pid})

    node_id_map = start_join(numNodes, existing_node_pid)
    # arbitrarily we choose numNodes*3 messages so that each node on average stores 3 messages
    IO.puts "number of messages stored in ring = #{numNodes*3}"
    #send_requests_from_children(node_id_map, numRequests)
    #listen(numNodes, numRequests)
    Process.sleep(5000)
  end

  defp start_join(numNodes, existing_node_pid, last_node_id \\0, node_id_map\\%{}) do
    supervisor_stats = DynamicSupervisor.count_children(__MODULE__)
    if (supervisor_stats.active < numNodes) do
      remainder = rem(@maxNumNodes, numNodes)
      new_node_id = get_unique_node_id(node_id_map)
      new_node_pid = join(existing_node_pid, new_node_id)
      node_id_map = Map.put(node_id_map, new_node_id, new_node_pid)
      Process.sleep(1_000)
      start_join(numNodes, existing_node_pid,new_node_id, node_id_map)
    else
      node_id_map
    end
  end

  defp join(existing_node_pid, new_node_id) do
    [succ_pid, hops] = GenServer.call(existing_node_pid, {:find_successor, new_node_id, 0})
    {:ok, new_node_pid} = add_node(new_node_id)
    GenServer.call(new_node_pid, {:set_succ, succ_pid})
    new_node_pid
  end

  defp get_unique_node_id(node_id_map) do
    rand_node_id = :rand.uniform(@maxNumNodes) - 1
    if Map.has_key?(node_id_map, rand_node_id) do
      get_unique_node_id(node_id_map)
    else
      rand_node_id
    end
  end

  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_node(node_id) do
    child = %{
      id: node_id,
      start: {ChordNode, :start_link, [%{:id => node_id, :node_identifier => :crypto.hash(:sha, Integer.to_string(node_id)) |> Base.encode16, :message_map => %{}, :requests_sent => 0, :pred_pid => nil, :super_pid => self()}]}
    }
    IO.puts "Added node #{node_id}"
    DynamicSupervisor.start_child(__MODULE__, child)
  end

  def remove_node(node_id, node_pid) do
    IO.puts "Removing node #{node_id}"
    DynamicSupervisor.terminate_child(__MODULE__, node_pid)
  end

  defp set_finger_tables_in_children(node_id_map) do

    Enum.each  node_id_map,  fn {node_id, node_pid} ->
      finger_table = get_finger_table(node_id, node_id_map, 0, [])
      GenServer.call(node_pid, {:set_finger_table, finger_table})
    end
  end

  defp get_finger_table(node_id, node_id_map, power, finger_table) do
    # Generating finger table as per paper
    cond do
      power == @m ->
        finger_table
      true ->
        next_node_id = get_next_node_id(node_id + :math.pow(2, power), node_id_map)
        finger_table = finger_table ++ [{next_node_id, Map.get(node_id_map, next_node_id)}]
        get_finger_table(node_id, node_id_map, power+1, finger_table)
    end
  end

  defp get_succ(node_id, node_id_map) do
    succ_id = get_next_node_id(node_id+1, node_id_map)
    succ_pid = Map.get(node_id_map, succ_id)
    [succ_id, succ_pid]
  end

  defp get_next_node_id(search_for_node, node_id_map) do
    search_for_node = rem(search_for_node |> round, @maxNumNodes) |> round
    cond do
      Map.has_key?(node_id_map, search_for_node) ->
        search_for_node
      true ->
        get_next_node_id(search_for_node + 1, node_id_map)
    end
  end

  defp send_requests_from_children(node_id_map, numRequests) do
    # sending requests as per input
    if numRequests > 0 do
      Enum.each  node_id_map,  fn {_node_id, node_pid} ->
        [_message, message_id, search_for_node] = get_random_request()
        #IO.puts "starting search from #{node_id} for #{search_for_node}"
        [node_id, hops] = GenServer.call(node_pid, {:find_successor, search_for_node, 0})
        Process.send(self(), {:message_found, node_id, hops}, [])
      end
      send_requests_from_children(node_id_map, numRequests-1)
    end
  end

  defp get_random_request() do
    message = :rand.uniform(1000000) |> Integer.to_string()
    message_id = :crypto.hash(:sha, message)  |> Base.encode16
    integer_message_id = String.to_integer(message_id, 16)
    bin_message_id = Integer.to_string(integer_message_id, 2)
    # we take the last m digits to get which node the message has to be stored at
    trunc_bin_message_id = String.slice(bin_message_id, -@m..-1)
    search_for_node = String.to_integer(trunc_bin_message_id,  2)
    [message, message_id, search_for_node]
  end

  defp store_messages_in_children(node_id_map, total_msg) do

    if total_msg > 0 do
      # I am generating random messages which are decimal numbers from 1 to 1000000
      [message, message_id, search_for_node] = get_random_request()
      node_id = get_next_node_id(search_for_node, node_id_map)
      node_pid = Map.get(node_id_map, node_id)
      # IO.puts "storing #{message} in #{node_id}"
      GenServer.call(node_pid, {:set_message, message_id, message})
      store_messages_in_children(node_id_map, total_msg-1)
    end
  end

  defp listen(numNodes, numRequests, num_messages_found\\0, total_hops\\0) do
    receive do
      {:message_found, _node_id, hops} ->
        #IO.puts "#{node_id} has the message. found in #{hops} hops"
        total_hops = total_hops + hops
        num_messages_found = num_messages_found + 1
        if num_messages_found < numNodes*numRequests do
          listen(numNodes, numRequests, num_messages_found, total_hops)
        else
          #IO.puts "Total hops made for #{numNodes} nodes each making #{numRequests} requests is #{total_hops}"
          IO.puts "Average hops for #{numNodes} nodes each making #{numRequests} requests is #{div(total_hops, numRequests*numNodes)}"
        end
    end
  end
end

defmodule ChordNode do
  use GenServer

  @m 4
  @maxNumNodes :math.pow(2, @m) |> round
  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(args) do
    # args %{id: 42, super_pid: #PID<0.88.0>}
    Process.send_after(self(), :poll, 1 * 1 * 180) # 3 seconds
    {:ok, args}
  end

  # Callbacks

  def handle_info(:poll, state) do
    GenServer.cast(self(), {:stabilize})
    Process.send_after(self(), :poll, 1 * 1 * 180) # 3 seconds
    {:noreply, state}
  end

  defp closest_preceding_node(finger_table, search_for_node, curr_node_id) do
    {node_id, node_pid} = Enum.find(finger_table, fn {node_id, node_pid} -> is_contained?(curr_node_id+1, node_id, search_for_node-1) end)
    node_pid
  end

  defp is_contained?(starting, id, ending) do
    ending = if ending < 0, do: @maxNumNodes-1, else: ending
    starting = rem(starting, @maxNumNodes) |> round
    ending = rem(ending, @maxNumNodes) |> round
    if(starting <= ending) do
      Enum.member?(starting..ending, id)
    else
      Enum.member?(starting..@maxNumNodes, id) || Enum.member?(0..ending, id)
    end
  end

  # scalable key location
  def handle_call({:find_successor, search_for_node, hops}, _from, state) do
    #IO.puts "Finding succ of #{search_for_node} from #{state.id}"
    succ_pid = state.succ_pid
    succ_id = if succ_pid == self(), do: state.id, else: GenServer.call(succ_pid, {:get_id})
    pred_pid = state.pred_pid
    pred_id = if pred_pid == self(), do: state.id, else: GenServer.call(pred_pid, {:get_id})
    finger_table = state.finger_table
    [node_pid, hops] = cond do
      is_contained?(pred_id+1, search_for_node, state.id) ->
        [self(), hops]
      is_contained?((state.id)+1, search_for_node, succ_id) ->
        [succ_pid, hops+1]
      true ->
        node_pid = closest_preceding_node(Enum.reverse(finger_table), search_for_node, state.id)
        #IO.puts "closest_preceding_node of #{search_for_node} in the finger table of #{state.id} is #{node_id}"
        GenServer.call(node_pid, {:find_successor, search_for_node, hops+1})
    end
    {:reply, [node_pid, hops], state}
  end

  def handle_call({:search_for_message, message_id, hops}, _from, state) do
    message_map = state.message_map
    cond do
      Map.has_key?(message_map, message_id) -> Map.get(message_map, message_id)
      true -> "Key does not exist"
    end
    {:reply, [state.id, hops], state}
  end

  def handle_call({:set_finger_table, finger_table}, _from, state) do
    state = Map.put(state, :finger_table, finger_table)
    # IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call({:set_succ, succ_pid}, _from, state) do
    state = Map.put(state, :succ_pid, succ_pid)
    #IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call({:set_pred, pred_pid}, _from, state) do
    state = Map.put(state, :pred_pid, pred_pid)
    # IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call( {:set_message, message_id, message}, _from, state) do
    message_map = Map.put(state.message_map, message_id, message)
    state = Map.put(state, :message_map, message_map)
    #IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call({:get_id}, _from, state) do
    {:reply, state.id, state}
  end

  def handle_call({:get_pred}, _from, state) do
    {:reply, state.pred_pid, state}
  end

  def handle_cast({:stabilize}, state) do
    succ_pid = state.succ_pid
    succ_id = if succ_pid == self(), do: state.id, else: GenServer.call(succ_pid, {:get_id})
    succesors_pred_pid = if succ_pid == self(), do: state.pred_pid, else: GenServer.call(succ_pid, {:get_pred})
    succesors_pred_id = if succesors_pred_pid == self(), do: state.id, else: GenServer.call(succesors_pred_pid, {:get_id})
    node_id = state.id
    state = if state.pred_pid == nil, do: Map.put(state, :pred_pid, self()), else: state

    state = cond do
      is_contained?(node_id+1, succesors_pred_id, succ_id-1) and succesors_pred_pid != self()->
        GenServer.call(succesors_pred_pid, {:set_pred, self()})
        Map.put(state, :succ_pid, succesors_pred_pid)
      is_contained?(succesors_pred_id+1, state.id, succ_id-1) and succesors_pred_pid != self() and succ_pid != self()->
        GenServer.call(succ_pid, {:set_pred, self()})
        GenServer.call(succesors_pred_pid, {:set_succ, self()})
        Map.put(state, :pred_pid, succesors_pred_pid)
      true ->
        state
    end

    pred_id = if state.pred_pid == self(), do: state.id, else: GenServer.call(state.pred_pid, {:get_id})
    succ_id = if state.succ_pid == self(), do: state.id, else: GenServer.call(state.succ_pid, {:get_id})
    IO.puts "node_id: #{node_id}; succ_id: #{succ_id}; pred_id: #{pred_id}"
    {:noreply, state}
  end

end

ChordRing.main
