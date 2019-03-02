defmodule Elixirc.Task.MessageParser do

  def call(full_string \\ "") do
    string_list = String.split(full_string, " ")
    structure(string_list, 0)
  end

  defp structure([_head | tail] = ["@" <> rest | _ ], field) when field < 1 do
    tag_map = read_tags(String.split(rest, ";"))
    map = structure(tail, 1)
    Map.put_new(map, :tags, tag_map)
  end
  
  defp structure([_head | tail] = [":" <> rest | _ ], field) when field < 2 do
    map = structure(tail, 2)
    Map.put_new(map, :source, rest)
  end
  
  defp structure([head | tail], field) when field < 3 do
    map = structure(tail, 3)
    Map.put_new(map, :command, head)
  end
    
  defp structure(string_list, field) when field == 3 do
    %{:params => string_list}
  end

  defp read_tags([head | tail]) do
    if String.contains?(head, "=") do
      pair = String.split(head, "=")
      [tag | tag_content ] = pair
      [val | _ ] = tag_content
      tag_map = read_tags(tail)
      Map.put_new(tag_map, tag, val)
    else
      tag_map = read_tags(tail)
      Map.put_new(tag_map, head, true)
    end
  end

  defp read_tags([]) do
    %{}
  end

end
