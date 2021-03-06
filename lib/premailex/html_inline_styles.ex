defmodule Premailex.HTMLInlineStyles do
  @moduledoc """
  Module that processes inline styling in HMTL.
  """

  alias Premailex.{CSSParser, Util}

  @doc false
  def process(html) do
    html
    |> Floki.find("style,link[rel=\"stylesheet\"][href]")
    |> Enum.map(&load_css(&1))
    |> Enum.filter(&!is_nil(&1))
    |> Enum.reduce([], &Enum.concat(&1, &2))
    |> Enum.reduce(Floki.parse(html), &add_rule_set_to_html(&1, &2))
    |> normalize_style()
    |> Floki.raw_html
  end

  defp load_css({"style", _, content}) do
    content
    |> Enum.join("\n")
    |> CSSParser.parse()
  end
  defp load_css({"link", attrs, _}),
    do: load_css({"link", List.keyfind(attrs, "href", 0)})
  defp load_css({"link", {"href", url}}) do
    url
    |> HTTPoison.get()
    |> parse_url_response()
  end

  defp parse_url_response({:ok, %{body: resp}}), do: CSSParser.parse(resp)
  defp parse_url_response(_), do: nil

  defp add_rule_set_to_html(%{selector: selector, rules: rules, specificity: specificity}, html) do
    html
    |> Floki.find(selector)
    |> Enum.reduce(html, &update_style_for_element(&2, &1, rules, specificity))
  end

  defp update_style_for_element(html, needle, rules, specificity) do
    Util.traverse(html, needle, fn {name, attrs, children} ->
      style = attrs
              |> Enum.into(%{})
              |> Map.get("style", nil)
              |> set_inline_style_specificity()
              |> add_styles_with_specificity(rules, specificity)

      attrs = attrs
              |> Enum.filter(fn {name, _} -> name != "style" end)
              |> Enum.concat([{"style", style}])

      {name, attrs, children}
    end)
  end

  defp set_inline_style_specificity(nil), do: ""
  defp set_inline_style_specificity(style) do
    if String.starts_with?(style, "[SPEC="),
      do: style,
      else: "[SPEC=1000[#{style}]]"
  end

  defp add_styles_with_specificity(style, rules, specificity) do
    "#{style}[SPEC=#{specificity}[#{CSSParser.to_string(rules)}]]"
  end

  defp normalize_style(html) do
    html
    |> Floki.find("[style]")
    |> Enum.reduce(html, &merge_style(&2, &1))
  end

  defp merge_style(html, needle) do
    Util.traverse(html, needle, fn {name, attrs, children} ->
      style = ~r/\[SPEC\=([\d]+)\[(.[^\]\]]*)\]\]/
              |> Regex.scan(attrs |> Enum.into(%{}) |> Map.get("style"))
              |> Enum.map(fn [_, specificity, rule] ->
                   %{specificity: specificity,
                     rules: CSSParser.parse_rules(rule)}
                 end)
              |> CSSParser.merge()
              |> CSSParser.to_string()

      attrs = attrs
              |> Enum.filter(fn {name, _} -> name != "style" end)
              |> Enum.concat([{"style", style}])

      {name, attrs, children}
    end)
  end
end
