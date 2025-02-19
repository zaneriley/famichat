defmodule FamichatWeb.Components.Typography do
  @moduledoc """
  A flexible typography component for rendering text elements with customizable styles.

  ## Example Usage

      <.typography locale={@user_locale} tag="h1" size="4xl" center={true}>Heading 1</.typography>
      <.typography locale={@user_locale} tag="p" size="md" dropcap={true}>Paragraph</.typography>
      <.typography locale={@user_locale} tag="p" size="1xs" font="cheee" color="accent">Special Text</.typography>

  """

  use Phoenix.Component
  require Logger

  @doc """
  Renders a typography element with the specified attributes.

  ## Attributes

    * `:tag` - The HTML tag to use (default: `"p"`).
    * `:size` - The text size, e.g., `"4xl"`, `"md"`, `"1xs"` (default: `"md"`).
    * `:center` - Centers the text if set to `true` (default: `false`).
    * `:id` - The HTML `id` attribute (optional).
    * `:color` - Additional text color classes (optional).
    * `:font` - The font variant to use, e.g., `"cardinal"`, `"cheee"` (optional).
    * `:dropcap` - Enables dropcap styling if set to `true` (default: `false`).
    * `:class` - Additional custom classes (optional).

  ## Examples

      <.typography locale={@user_locale} tag="h1" size="4xl" center={true}>Heading 1</.typography>

      <.typography locale={@user_locale} tag="p" size="md" dropcap={true}>Paragraph</.typography>

      <.typography locale={@user_locale} tag="p" size="1xs" font="cheee" color="accent">Special Text</.typography>

  """
  @spec typography(map()) :: Phoenix.LiveView.Rendered.t()
  attr :tag, :string, default: "p"
  attr :size, :string, default: "md"
  attr :center, :boolean, default: false
  attr :id, :string, default: nil
  attr :color, :string, default: nil
  attr :font, :string, default: nil
  attr :dropcap, :boolean, default: false
  attr :class, :string, default: nil
  slot :inner_block, required: true

  alias FamichatWeb.Components.TypographyHelpers

  def typography(assigns) do
    all_classes = TypographyHelpers.build_class_names(assigns)

    assigns =
      assigns
      |> assign(:all_classes, all_classes)
      |> assign(:optical_adjustment_class, "optical-adjustment")

    ~H"""
    <.dynamic_tag name={@tag} id={@id} class={@all_classes}>
      <span class={@optical_adjustment_class}>
        <%= if @dropcap do %>
          <% text =
            render_slot(@inner_block)
            |> Phoenix.HTML.Safe.to_iodata()
            |> IO.iodata_to_binary()
            |> String.trim() %>
          <%= if starts_with_hanging_punct?(text) do %>
            <% {hanging_punct, rest} = String.split_at(text, 1) %>
            <span class="dropcap hanging-punct font-noto-sans-jp" aria-hidden="true">
              <span class="hanging-punct"><%= hanging_punct %></span><span><%= rest %></span>
            </span>
            <span class="sr-only"><%= text %></span>
          <% else %>
            <% {first_char, rest} = String.split_at(text, 1) %>
            <span aria-hidden="true">
              <span class="dropcap font-noto-serif-jp"><%= first_char %></span><span><%= rest %></span>
            </span>
            <span class="sr-only"><%= text %></span>
          <% end %>
        <% else %>
          <%= render_slot(@inner_block) %>
        <% end %>
      </span>
    </.dynamic_tag>
    """
  end

  @doc """
  Determines if the given text starts with hanging punctuation.

  ## Parameters

    - `text` - The text string to analyze.

  ## Returns

    - `true` if the text starts with a hanging punctuation mark, otherwise `false`.
  """
  @spec starts_with_hanging_punct?(String.t()) :: boolean()
  def starts_with_hanging_punct?(text) when is_binary(text) do
    hanging_punctuations = [
      ",",
      ".",
      "،",
      "۔",
      "、",
      "。",
      "，",
      "．",
      "﹐",
      "﹑",
      "﹒",
      "｡",
      "､",
      "：",
      "？",
      "！",
      "\"",
      "'",
      "“",
      "”",
      "‘",
      "’",
      "„",
      "‟",
      "«",
      "»",
      "‹",
      "›",
      "「",
      "」",
      "『",
      "』",
      "《",
      "》",
      "〈",
      "〉"
    ]

    case String.graphemes(text) do
      [first | _] -> first in hanging_punctuations
      [] -> false
    end
  end
end
