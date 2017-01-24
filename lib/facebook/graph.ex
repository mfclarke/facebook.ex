defmodule Facebook.Graph do
  require Logger

  alias Facebook.Config

  @moduledoc """
  HTTP Wrapper for the Graph API using hackney.
  """

  @doc """
  Start the API
  """
  @spec start_link :: :ok
  def start_link do
    :ignore
  end

  @type path :: String.t
  @type response :: {:json, HashDict.t} | {:body, String.t}
  @type options :: list
  @type params :: list
  @type method :: :get | :post | :put | :head
  @type url :: String.t
  @type payload :: binary

  @doc """
  HTTP GET using a path
  """
  @spec get(path) :: response
  def get(path) do
    get(path, [], [])
  end

  @doc """
  HTTP GET using path and params
  """
  @spec get(path, params) :: response
  def get(path, params) do
    get(path, params, [])
  end

  @doc """
  HTTP GET using path, params and options
  """
  @spec get(path, params, options) :: response
  def get(path, params, options) do
    url = :hackney_url.make_url(Config.graph_url, path, params)
    request(:get, url, options)
  end

  @spec post(path, params) :: response
  def post(path, params) do
    post(path, params, [])
  end

  @spec post(path, params, options) :: response
  def post(path, params, options) do
    url = :hackney_url.make_url(Config.graph_url, path, params)
    request(:post, url, options)
  end

  @spec request(method, url, options) :: response
  defp request(method, url, options) do
    request(method, url, <<>>, options)
  end

  # Handle this:
  # {
  #   "error": {
  #     "message": "(#4) Application request limit reached",
  #     "type": "OAuthException",
  #     "is_transient": true,
  #     "code": 4,
  #     "fbtrace_id": "HMoEZxU6YQn"
  #   }
  # }

  # Handle this: (header)
  # "X-App-Usage" => {
  #   "call_count" => x,
  #   "total_time" => y,
  #   "total_cputime" => z
  # }

  # [{"x-app-usage",
  #  "{\"call_count\":241,\"total_cputime\":67,\"total_time\":85}"},
  # {"x-fb-rev", "2503827"}, {"x-fb-trace-id", "FmuNEgEvJYd"},
  # {"Content-Type", "text/javascript; charset=UTF-8"},
  # {"facebook-api-version", "v2.7"}, {"Cache-Control", "no-store"},
  # {"Pragma", "no-cache"}, {"Access-Control-Allow-Origin", "*"},
  # {"Expires", "Sat, 01 Jan 2000 00:00:00 GMT"},
  # {"WWW-Authenticate",
  #  "OAuth \"Facebook Platform\" \"invalid_request\" \"(#4) Application request limit reached\""},
  # {"X-FB-Debug",
  #  "r8I6JeiNJoIZAfWBqpTk4nqGb+g3qb7OpCNGnJuvb4Y2tks0yn720tx4OIfqH/MVu+4JUiFHk0vDudZ3Z1jSlA=="},
  # {"Date", "Sat, 13 Aug 2016 12:26:56 GMT"}, {"Connection", "keep-alive"},
  # {"Content-Length", "142"}], #Reference<0.0.5.530>}

  @spec request(method, url, payload, options) :: response
  defp request(method, url, payload, options) do
    headers = []
    Logger.info fn ->
      "[#{method}] #{url} #{inspect headers} #{inspect payload}"
    end
    case :hackney.request(method, url, headers, payload, options) do
      {:ok, 403, [{"x-app-usage", usage_string} | _], client_ref} ->
        {:ok, body} = :hackney.body(client_ref)
        Logger.error fn ->
          "FB Usage reached. Details: #{usage_string}"
        end
        handle_body body

      {:ok, 200, [{"x-app-usage", usage_string} | _], client_ref} ->
        {:ok, body} = :hackney.body(client_ref)
        Logger.warn fn ->
          "FB Usage nearly reached. Details: #{usage_string}"
        end
        case JSON.decode(body) do
          {:ok, data} ->
            {:json, Map.put(data, "app_usage", usage_string)}
          _ ->
            {:body, body}
        end

      {:ok, _status_code, _headers, client_ref} ->
        {:ok, body} = :hackney.body(client_ref)
        Logger.debug fn ->
          "body: #{inspect body}"
        end
        handle_body body

      error ->
        Logger.error fn ->
          "error: #{inspect error}"
        end
        error
    end
  end

  defp handle_body(body) do
    case JSON.decode(body) do
      {:ok, data} ->
        {:json, data}
      _ ->
        {:body, body}
    end
  end
end
