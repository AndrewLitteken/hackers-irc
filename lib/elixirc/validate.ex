defmodule Elixirc.Validate do
  require Logger

  def validate(params, param_specs) do
    check_param(params, param_specs)
  end

  defp check_param([] = param, [] = spec) do
    if param == spec do
        {:ok, nil}
    else
        {:error, "parameter and specification mismatch"}
    end
  end
  
    defp check_param([param_head | param_tail] = param, [spec_head | spec_tail] = spec) do
      Logger.info(inspect(spec_head))
      result = case spec_head do
        {:matches, string} ->
          if string == param_head do
            {:ok, nil}
          else
            {:error, "string "<>param_head<>" does not match "<>string}
          end
        {:starts, string} ->
          case String.starts_with?(param_head, string)do
            true -> {:ok, nil}
            _ -> {:error, param_head<>"does not start with "<>string}
          end
        {:pattern, string} ->
          {:ok, test} = Regex.compile(string)
          case Regex.match?(test, param_head) do
            true -> {:ok, nil}
            false -> {:error, "pattern does match for "<>param_head}
          end
        {:or, specs} ->
          check_multiple(param_head, specs)
        {:option, spec} -> 
          case check_param(param, [spec] ++ spec_tail) do
            {:ok, _} -> {:ok, nil}
            _ -> check_param(param, spec_tail)
          end
      end 
      ret = case result do
        {:ok, _} -> check_param(param_tail, spec_tail)
        {:error, _} -> {:error, "parameter mismatch"}
      end
      ret
  end
  

  defp check_multiple(param, [spec_head | spec_tail]) do
    case check_param([param], [spec_head]) do
        {:ok, _} -> {:ok, nil}
        _ -> check_multiple(param, spec_tail)
    end
  end

  defp check_multiple(param, []) do
    {:error, param<>" does not match given specification"}
  end


end
