defmodule Elixirc.Task.Validate do

  def call(params, param_specs) do
    check_param(params, param_specs)
  end

  defp check_param([param_head | param_tail] = param, [spec_head | spec_tail]) do
    case spec_head do
        {:matches, string} ->
          if string == param_head do
            {:ok, nil}
          else
            {:error, "string "<>param_head<>" does not match "<>string}
        {:starts, string} ->
          case param_head do
            string <> rest -> {:ok, nil}
            _ -> {:error, param_head<>"does not start with "<>string}
        {:pattern, string} ->
          case Regex.match?(string, param_head) do
            true -> {:ok, nil}
            false -> {:error, "pattern does match for "<>param_head}
        {:or, specs} ->
          check_multiple(param_head, specs)
        {:option, spec} -> 
          case check_param(param, [spec] ++ spec_tail) do
            {:ok, _} -> {:ok, nil}
            _ -> check_param(param, spec_tail)
          end
        end 
    end
    |> case do
      {:ok, _} -> check_param(param_tail, spec_tail)
      _ -> result
    end
  end

  defp check_multiple(param, [spec_head | spec_tail) do
    case check_param([param], [spec_head]) do
        {:ok, _} -> {:ok, nil}
        _ -> check_multiple(param, spec_tail)
  end

  defp check_multiple(param, []) do
    {:error, param<>" does not match given specification"}
  end

  defp check_param([], []) do
    {:ok, nil}
  end
  
  defp check_param(param, []) do
    {:error, "specification not complete"}
  end

  defp check_param([], spec) do
    {:error, "specifications specify additional paramters"}
  end

end
