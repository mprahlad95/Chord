
# The input provided will be of the form:
# proj3.exs numNodes numRequests
# Where numNodes is the number of peers to be created in the peer to peer
# system and numRequests the number of requests each peer has to make. When
# all peers performed that many requests, the program can exit. Each peer should
# send a request/second.
# Output: Print the average number of hops (node connections) that have to
# be traversed to deliever a message.

defmodule ChordRing do
  use Supervisor

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
    m =
      numNodes
      |> :math.log2
      |> :math.ceil
      |> round
    IO.puts "m = #{m}"
    maxNumNodes = :math.pow(2, m) |> round

    {:ok, super_pid} = start_link(numNodes, maxNumNodes)

    node_id_map = make_id_map(%{}, Supervisor.which_children(super_pid))
    set_finger_tables_in_children(node_id_map, m, maxNumNodes)
    # arbitrarily we choose numNodes*3 messages so that each node on average stores 3 messages
    store_messages_in_children(node_id_map, m, maxNumNodes, numNodes*3)
    IO.puts "number of messages stored in ring = #{numNodes*3}"
    send_requests_from_children(node_id_map, numRequests, m, maxNumNodes)
    listen(numNodes, numRequests)
    Process.sleep(1000)
  end

  def start_link(numNodes, maxNumNodes) do

    r = rem(maxNumNodes, numNodes)

    children = get_children_list([], 0, r, numNodes)
    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp get_children_list(children_list, currNode, remainder, totalNodes) do
    nextNode = if remainder > 0, do: currNode + 2, else: currNode + 1
    if totalNodes == 0 do
      children_list
    else
      [%{
        id: currNode,
        start: {ChordNode, :start_link, [%{:id => currNode, :node_identifier => :crypto.hash(:sha, Integer.to_string(currNode)) |> Base.encode16, :message_map => %{}, :requests_sent => 0, :super_pid => self()}]}
      }] ++ get_children_list(children_list, nextNode, remainder - 1, totalNodes - 1)
    end
  end

  defp make_id_map(node_ids_map, [node_obj | node_objs]) do
    {_, node_pid, _, _} = node_obj
    node_id = GenServer.call(node_pid, {:get_id})
    node_ids_map = Map.put(node_ids_map, node_id, node_pid)
    make_id_map(node_ids_map, node_objs)
  end

  defp make_id_map(node_ids_map, []) do
    node_ids_map
  end

  defp set_finger_tables_in_children(node_id_map, m, maxNumNodes) do

    Enum.each  node_id_map,  fn {node_id, node_pid} ->
      neighbor_list = get_neighbor_list(node_id, node_id_map, m, maxNumNodes, 0, [])
      [succ_id, succ_pid] = get_succ(node_id, node_id_map, maxNumNodes)
      GenServer.call(node_pid, {:set_finger_table, neighbor_list, succ_id, succ_pid})
      GenServer.call(succ_pid, {:set_prev, node_id, node_pid})
    end
  end

  defp get_neighbor_list(node_id, node_id_map, m, maxNumNodes, power, neighbor_list) do
    cond do
      power == m ->
        neighbor_list
      true ->
        next_node_id = get_next_node_id(node_id + :math.pow(2, power), node_id_map, maxNumNodes)
        neighbor_list = neighbor_list ++ [{next_node_id, Map.get(node_id_map, next_node_id)}]
        get_neighbor_list(node_id, node_id_map, m, maxNumNodes, power+1, neighbor_list)
    end
  end

  defp get_succ(node_id, node_id_map, maxNumNodes) do
    succ_id = get_next_node_id(node_id+1, node_id_map, maxNumNodes)
    succ_pid = Map.get(node_id_map, succ_id)
    [succ_id, succ_pid]
  end

  defp get_next_node_id(search_for_node, node_id_map, maxNumNodes) do
    search_for_node = rem(search_for_node |> round, maxNumNodes) |> round
    cond do
      Map.has_key?(node_id_map, search_for_node) ->
        search_for_node
      true ->
        get_next_node_id(search_for_node + 1, node_id_map, maxNumNodes)
    end
  end

  defp send_requests_from_children(node_id_map, numRequests, m, maxNumNodes) do
    if numRequests > 0 do
      Enum.each  node_id_map,  fn {_node_id, node_pid} ->
        [_message, message_id, search_for_node] = get_random_request(m)
        #IO.puts "starting search from #{node_id} for #{search_for_node}"
        [node_id, hops] = GenServer.call(node_pid, {:find_successor, search_for_node, 0, message_id, maxNumNodes})
        Process.send(self(), {:message_found, node_id, hops}, [])
      end
      send_requests_from_children(node_id_map, numRequests-1, m,  maxNumNodes)
    end
  end

  defp get_random_request(m) do
    message = :rand.uniform(1000000) |> Integer.to_string()
    message_id = :crypto.hash(:sha, message)  |> Base.encode16
    integer_message_id = String.to_integer(message_id, 16)
    bin_message_id = Integer.to_string(integer_message_id, 2)
    # we take the last m digits to get which node the message has to be stored at
    trunc_bin_message_id = String.slice(bin_message_id, -m..-1)
    search_for_node = String.to_integer(trunc_bin_message_id,  2)
    [message, message_id, search_for_node]
  end

  defp store_messages_in_children(node_id_map, m, maxNumNodes, total_msg) do

    if total_msg > 0 do
      # I am generating random messages which are decimal numbers from 1 to 1000000
      [message, message_id, search_for_node] = get_random_request(m)
      node_id = get_next_node_id(search_for_node, node_id_map, maxNumNodes)
      node_pid = Map.get(node_id_map, node_id)
      # IO.puts "storing #{message} in #{node_id}"
      GenServer.call(node_pid, {:set_message, message_id, message})
      store_messages_in_children(node_id_map, m, maxNumNodes, total_msg-1)
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

  def init(args) do
    {:ok, args}
  end
end

defmodule ChordNode do
  use GenServer
  def start_link(state) do
    GenServer.start_link(__MODULE__, state)
  end

  def init(args) do
    # args %{id: 42, super_pid: #PID<0.88.0>}
    {:ok, args}
  end

  defp closest_preceding_node(finger_table, search_for_node, curr_node_id, maxNumNodes) do
    Enum.find(finger_table, fn {x, _} -> belongs(x, curr_node_id+1, search_for_node-1, maxNumNodes) end)
  end

  defp belongs(id, starting, ending, maxNumNodes) do
    ending = if ending < 0, do: maxNumNodes-1, else: ending
    starting = rem(starting, maxNumNodes) |> round
    ending = rem(ending, maxNumNodes) |> round
    if(starting <= ending) do
      Enum.member?(starting..ending, id)
    else
      Enum.member?(starting..maxNumNodes, id) || Enum.member?(0..ending, id)
    end
  end

  # scalable key location
  def handle_call({:find_successor, search_for_node, hops, message_id, maxNumNodes}, _from, state) do
    #IO.puts "Finding succ of #{search_for_node} from #{state.id}"
    succ_id = state.succ_id
    succ_pid = state.succ_pid
    finger_table = state.finger_table
    [node_id, hops] = cond do
      belongs(search_for_node, (state.prev_id)+1, state.id, maxNumNodes) ->
        [state.id, hops]
      belongs(search_for_node, (state.id)+1, succ_id, maxNumNodes) ->
        GenServer.call(succ_pid, {:search_for_message, message_id, hops+1})
      true ->
        {_node_id, node_pid} = closest_preceding_node(Enum.reverse(finger_table), search_for_node, state.id, maxNumNodes)
        #IO.puts "closest_preceding_node of #{search_for_node} in the finger table of #{state.id} is #{node_id}"
        GenServer.call(node_pid, {:find_successor, search_for_node, hops+1, message_id, maxNumNodes})
    end
    {:reply, [node_id, hops], state}
  end

  def handle_call({:search_for_message, message_id, hops}, _from, state) do
    message_map = state.message_map
    cond do
      Map.has_key?(message_map, message_id) -> Map.get(message_map, message_id)
      true -> "Key does not exist"
    end
    {:reply, [state.id, hops], state}
  end

  def handle_call({:set_finger_table, finger_table, succ_id, succ_pid}, _from, state) do
    state = Map.put(state, :finger_table, finger_table)
    state = Map.put(state, :succ_id, succ_id)
    state = Map.put(state, :succ_pid, succ_pid)
    # IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call({:set_prev, prev_id, prev_pid}, _from, state) do
    state = Map.put(state, :prev_id, prev_id)
    state = Map.put(state, :prev_pid, prev_pid)
    #IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call( {:set_message, message_id, message}, _from, state) do
    message_map = Map.put(state.message_map, message_id, message)
    state = Map.put(state, :message_map, message_map)
    # IO.inspect state
    {:reply, :ok, state}
  end

  def handle_call({:get_id}, _from, state) do
    {:reply, state.id, state}
  end

end

ChordRing.main
