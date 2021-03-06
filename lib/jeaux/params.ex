defmodule Jeaux.Params do
  @moduledoc false

  def compare(params, schema) do
    params
    |> ProperCase.to_snake_case
    |> keys_to_atoms
    |> apply_defaults(schema)
    |> validate_required(schema)
    |> parse_into_types(schema)
    |> validate_types(schema)
    |> validate_min(schema)
    |> validate_max(schema)
    |> validate_valid(schema)
    |> validate_nested(schema)
  end

  defp keys_to_atoms(params) do
    keys = Map.keys(params)
    convert_all_keys(keys, params)
  end

  defp convert_all_keys([], _params), do: %{}
  defp convert_all_keys([k | tail], params) when is_binary(k) do
    if is_map(params[k]) do
      Map.put(convert_all_keys(tail, params), String.to_atom(k), keys_to_atoms(params[k]))
    else
      Map.put(convert_all_keys(tail, params), String.to_atom(k), params[k])
    end
  end
  defp convert_all_keys([k | tail], params) do
    if is_map(params[k]) do
      Map.put(convert_all_keys(tail, params), k, keys_to_atoms(params[k]))
    else
      Map.put(convert_all_keys(tail, params), k, params[k])
    end
  end

  defp apply_defaults(params, schema) do
    param_keys = Map.keys(params)

    default_schema_keys =
      schema
      |> Enum.filter(fn({_k, v}) ->
        case is_map(v)  do
          true  -> false
          false -> Keyword.get(v, :default) !== nil
        end
      end)
      |> Keyword.keys
      |> Enum.filter(&(!Enum.member?(param_keys, &1) || params[&1] === nil))

    add_defaults(params, schema, default_schema_keys)
  end

  defp validate_required(params, schema) do
    param_keys = Map.keys(params)

    compared_params =
      schema
      |> Enum.filter(fn({_k, v}) ->
        case is_map(v) do
          true  -> false
          false -> Keyword.get(v, :required) === true
        end
      end)
      |> Keyword.keys
      |> Enum.drop_while(fn(required_param) -> Enum.member?(param_keys, required_param) end)

    case Enum.empty?(compared_params) do
      true  -> {:ok, params}
      false ->
        [first_required_param | _tail] = compared_params
        {:error, "#{first_required_param} is required."}
    end
  end

  defp parse_into_types({:error, message}, _schema), do: {:error, message}
  defp parse_into_types({:ok, params}, schema) do
    params_keys = Map.keys(params)

    {:ok, check_and_format_types(params, schema, params_keys)}
  end

  defp validate_types({:error, message}, _schema), do: {:error, message}
  defp validate_types({:ok, params}, schema) do
    errors = Enum.reduce params, [], fn {k, v}, error_list  ->
      type =
        case is_map(schema[k])  do
          true  -> nil
          false -> Keyword.get(schema[k] || [], :type)
        end

      validate_type({k, v}, schema[k], type) ++ error_list
    end

    case Enum.empty?(errors) do
      true  -> {:ok, params}
      false ->
        [first_error | _tail] = errors
        first_error
    end
  end

  defp check_and_format_types(params, _schema, []), do: params
  defp check_and_format_types(params, schema, [k | tail]) do
    expected_type =
      case is_map(schema[k]) do
        true  -> nil
        false -> Keyword.get(schema[k] || [], :type)
      end

    is_expected? =
      case expected_type do
        :list    -> is_list(params[k])
        :string  -> is_binary(params[k])
        :guid    -> is_binary(params[k])
        :float   -> is_float(params[k])
        :integer -> is_integer(params[k])
        :boolean -> is_boolean(params[k])
        nil      -> true
      end

      case is_expected? do
        true  -> Map.put(check_and_format_types(params, schema, tail), k, params[k])
        false ->
          parsed_value = try_to_parse(params[k], expected_type)
          Map.put(check_and_format_types(params, schema, tail), k, parsed_value)
      end
  end

  defp try_to_parse(value, :string), do: to_string(value)
  defp try_to_parse(value, :guid), do: to_string(value)
  defp try_to_parse(value, :float) when is_integer(value), do: String.to_float("#{value}.0")
  defp try_to_parse(value, :float) when is_binary(value) do
    case Float.parse(value)  do
      {v, _} -> v
      :error -> value
    end
  end
  defp try_to_parse(value, :integer) when is_binary(value) do
    case Integer.parse(value)  do
      {v, _} -> v
      :error -> value
    end
  end
  defp try_to_parse(value, :integer) when is_float(value), do: round(value)
  defp try_to_parse(value, :list) when is_binary(value), do: String.split(value, ",")
  defp try_to_parse(value, :list), do: value
  defp try_to_parse("true", :boolean), do: true
  defp try_to_parse("false", :boolean), do: false
  defp try_to_parse(value, :boolean), do: value


  defp validate_min({:error, message}, _schema), do: {:error, message}
  defp validate_min({:ok, params}, schema) do
    minimum_schema_keys =
      schema
      |> Enum.filter(fn({_k, v}) ->
        case is_map(v) do
          true  -> false
          false -> Keyword.get(v, :min) !== nil
        end
      end)
      |> Keyword.keys

    errors = Enum.reduce minimum_schema_keys, [], fn k, error_list  ->
      minimum = Keyword.get(schema[k], :min)

      case params[k] >= minimum do
        true  -> [] ++ error_list
        false -> [{:error, "#{k} must be greater than or equal to #{minimum}"}] ++ error_list
      end
    end

    case Enum.empty?(errors) do
      true  -> {:ok, params}
      false ->
        [first_error | _tail] = errors
        first_error
    end
  end

  defp validate_max({:error, message}, _schema), do: {:error, message}
  defp validate_max({:ok, params}, schema) do
    maximum_schema_keys =
      schema
      |> Enum.filter(fn({_k, v}) ->
        case is_map(v) do
          true  -> false
          false -> Keyword.get(v, :max) !== nil
        end
      end)
      |> Keyword.keys

    errors = Enum.reduce maximum_schema_keys, [], fn k, error_list  ->
      maximum = Keyword.get(schema[k], :max)

      case params[k] <= maximum do
        true  -> [] ++ error_list
        false -> [{:error, "#{k} must be less than or equal to #{maximum}"}] ++ error_list
      end
    end

    case Enum.empty?(errors) do
      true  -> {:ok, params}
      false ->
        [first_error | _tail] = errors
        first_error
    end
  end

  defp validate_valid({:error, message}, _schema), do: {:error, message}
  defp validate_valid({:ok, params}, schema) do
    valid_keys =
      schema
      |> Enum.filter(fn({_k, v}) ->
        case is_map(v) do
          true  -> false
          false -> Keyword.get(v, :valid) !== nil
        end
      end)
      |> Keyword.keys

    errors = Enum.reduce valid_keys, [], fn k, error_list ->
      vals = Keyword.get(schema[k], :valid)

      valid_values =
        case is_list(vals) do
          true  -> vals
          false -> [vals]
        end

      case Enum.any?(valid_values, &(&1 === params[k])) do
        true  -> [] ++ error_list
        false -> [{:error, "#{k} is not a valid value."}]
      end

    end

    case Enum.empty?(errors) do
      true  -> {:ok, params}
      false ->
        [first_error | _tail] = errors
        first_error
    end
  end

  defp validate_type({k, _v}, nil, _type), do: [{:error, "#{k} is not a valid parameter"}]
  defp validate_type(_param, _schema, nil), do: []
  defp validate_type({k, v}, _schema, :integer) do
    case is_integer(v) do
      true  -> []
      false -> [{:error, "#{k} must be an integer."}]
    end
  end

  defp validate_type({k, v}, _schema, :float) do
    case is_float(v) do
      true  -> []
      false -> [{:error, "#{k} must be a float."}]
    end
  end

  defp validate_type({k, v}, _schema, :string) do
    case is_binary(v) do
      true  -> []
      false -> [{:error, "#{k} must be a string."}]
    end
  end

  defp validate_type({k, v}, _schema, :list) do
    case is_list(v) do
      true  -> []
      false -> [{:error, "#{k} must be a list."}]
    end
  end

  defp validate_type({k, v}, _schema, :guid) do
    case guid_match?(v) do
      true  -> []
      false -> [{:error, "#{k} must be in valid guid format."}]
    end
  end

  defp validate_type({k, v}, _schema, :boolean) do
    case is_boolean(v) do
      true  -> []
      false -> [{:error, "#{k} must be a boolean."}]
    end
  end

  defp add_defaults(params, _schema, []), do: params
  defp add_defaults(params, schema, [k | tail]) do
    default = Keyword.get(schema[k], :default)

    Map.put(add_defaults(params, schema, tail), k, default)
  end

  defp validate_nested({:error, message}, _schema), do: {:error, message}
  defp validate_nested({:ok, params}, schema) do
    keys_with_maps =
      schema
      |> Enum.filter(fn({_k, v}) -> is_map(v) end)
      |> Keyword.keys

    case each_nested(keys_with_maps, params, schema) do
      {:error, message} -> {:error, message}
      new_params        -> {:ok, new_params}
    end
  end

  defp each_nested([], params, _schema), do: params
  defp each_nested([k | tail], params, schema) do
    case is_map(params[k]) do
      true  ->
        case Jeaux.validate(params[k], schema[k]) do
          {:ok, new_params} -> Map.put(each_nested(tail, params, schema), k, new_params)
          {:error, message} -> {:error, message}
        end

      false -> {:error, "expected #{k} to be a map"}
    end
  end

  defp guid_match?(v) do
    Regex.match?(~r/\A[A-F0-9]{8}(?:-?[A-F0-9]{4}){3}-?[A-F0-9]{12}\z/i, v) ||
    Regex.match?(~r/\A\{[A-F0-9]{8}(?:-?[A-F0-9]{4}){3}-?[A-F0-9]{12}\}\z/i, v)
  end
end
