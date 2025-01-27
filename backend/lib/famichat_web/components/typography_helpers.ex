defmodule FamichatWeb.Components.TypographyHelpers do
  @moduledoc """
  Provides helper functions for building typography-related CSS class names with locale-specific font mappings.

  This module generates consistent and flexible class names for text elements, handling typography options such as font size,
  font family, color, alignment, and locale-specific font substitutions.

  ## Locale-Specific Font Mappings

  The `font_variants` map defines font keys that map to locale-specific font classes. This allows the same `:font` assign to use
  different fonts based on the current locale, ensuring appropriate typefaces are used for different languages.

  ## Usage

  The main function `build_class_names/2` takes a map of assigns and returns a string of CSS class names. It supports the following options:

  - `:font` - Specifies the logical font key (e.g., `"cardinal"`, `"cheee"`, `"flexa"`). The actual font applied depends on the current locale.
  - `:color` - Sets the text color (e.g., `"main"`, `"callout"`, `"deemphasized"`).
  - `:size` - Determines the font size (e.g., `"4xl"`, `"3xl"`, `"2xl"`, `"md"`).
  - `:center` - Boolean to center-align the text.
  - `:class` - Additional custom classes to be appended.
  - `:dropcap` - Boolean to apply dropcap styling.

  ### Example

      iex> assigns = %{font: "cardinal", size: "2xl", center: true, class: "custom-class", dropcap: true}
      iex> FamichatWeb.Components.TypographyHelpers.build_class_names(assigns)
      "text-2xl text-center text-callout font-cardinal-fruit custom-class dropcap"

  """

  # Move configuration to module attributes
  @size_classes %{
    "4xl" => "text-4xl",
    "3xl" => "text-3xl",
    "2xl" => "text-2xl",
    "1xl" => "text-1xl",
    "md" => "text-md",
    "1xs" => "text-1xs",
    "2xs" => "text-2xs"
  }

  @color_classes %{
    "main" => "text-main",
    "callout" => "text-callout",
    "deemphasized" => "text-deemphasized",
    "suppressed" => "text-suppressed",
    "accent" => "text-accent"
  }

  @font_default_colors %{
    "cheee" => "deemphasized"
  }

  @font_variants %{
    "cardinal" => %{
      "en" => "font-cardinal-fruit",
      "ja" => "font-noto-serif-jp"
    },
    "cheee" => %{
      "en" => "font-cheee tracking-widest",
      "ja" => "font-noto-sans-jp bold"
    },
    "flexa" => %{
      "en" => "font-gt-flexa",
      "ja" => "font-ud-reimin"
    },
    "noto" => %{
      "en" => "font-noto-sans-jp",
      "ja" => "font-noto-sans-jp"
    }
  }

  @doc """
  Builds a string of CSS class names based on the provided typography-related options.

  ## Parameters

    - `assigns` - A map containing typography options. Supported keys are:
      - `:font` - String, the logical font key.
      - `:color` - String, the text color name.
      - `:size` - String, the font size (default: `"md"`).
      - `:center` - Boolean, whether to center-align the text (default: `false`).
      - `:class` - String, additional custom classes (default: `""`).
      - `:dropcap` - Boolean, whether to apply dropcap styling (default: `false`).

  ## Returns

    - A string of space-separated CSS class names.

  ## Examples

      iex> build_class_names(%{font: "cheee", size: "1xl", dropcap: true})
      "text-1xl text-callout font-cheee tracking-widest dropcap"

      iex> build_class_names(%{color: "accent", center: true, dropcap: true})
      "text-md text-center text-accent font-gt-flexa dropcap"

  """
  @spec build_class_names(map(), String.t() | nil) :: String.t()
  def build_class_names(assigns, locale \\ nil) do
    locale = locale || assigns[:locale] || Gettext.get_locale()
    font = assigns[:font] || default_font_for_locale(locale)

    %{
      size: assigns[:size] || "md",
      center: Map.get(assigns, :center, false),
      color: assigns[:color],
      class: assigns[:class] || "",
      font: font,
      locale: locale
    }
    |> build_all_classes()
    |> Enum.filter(&(&1 != ""))
    |> Enum.join(" ")
  end

  @spec build_all_classes(map()) :: list(String.t())
  defp build_all_classes(opts) do
    [
      build_base_classes(opts),
      get_color_class(opts),
      get_font_classes(opts.font, opts.locale),
      opts.class
    ]
    |> List.flatten()
  end

  @spec build_base_classes(map()) :: list(String.t())
  defp build_base_classes(%{size: size, center: center}) do
    [
      Map.get(@size_classes, size, ""),
      if(center, do: "text-center", else: "")
    ]
  end

  @spec get_color_class(map()) :: String.t()
  defp get_color_class(%{color: color, font: font}) do
    color = resolve_color(color, font)
    Map.get(@color_classes, color, "")
  end

  @spec resolve_color(String.t() | nil, String.t()) :: String.t()
  defp resolve_color(nil, font), do: Map.get(@font_default_colors, font, "main")
  defp resolve_color(color, _font), do: color

  @spec get_font_classes(String.t(), String.t()) :: String.t()
  defp get_font_classes(font, locale) do
    case @font_variants[font] do
      %{} = locales -> Map.get(locales, locale, locales["en"])
      nil -> ""
    end
  end

  @spec default_font_for_locale(String.t()) :: String.t()
  defp default_font_for_locale("ja"), do: "noto"
  defp default_font_for_locale(_), do: "flexa"
end
