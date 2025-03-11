/**
 * Theme Switcher Module
 *
 * This module initializes and manages the theme toggling functionality.
 * It synchronizes the theme between user preferences stored in localStorage
 * and system preferences, applying the appropriate data-theme attribute to the <html> element.
 */

export function initThemeToggle() {
  // Reference to the root element
  const root = document.documentElement;

  // Theme constants
  const THEME_LIGHT = "light";
  const THEME_DARK = "dark";
  const THEME_SYSTEM = "system";

  // Key for localStorage
  const STORAGE_KEY = "theme";

  // Check for localStorage availability
  let storageAvailable = true;
  try {
    const testKey = "__storage_test__";
    localStorage.setItem(testKey, testKey);
    localStorage.removeItem(testKey);
  } catch (e) {
    storageAvailable = false;
  }

  // Function to set theme attribute on the root element
  const applyTheme = (theme: string) => {
    if (theme === THEME_SYSTEM) {
      root.removeAttribute("data-theme");
    } else {
      root.setAttribute("data-theme", theme);
    }
  };

  // Function to get stored user preference
  const getUserPreference = (): string | null => {
    const preference = storageAvailable
      ? localStorage.getItem(STORAGE_KEY)
      : null;
    return preference;
  };

  // Function to save user preference
  const saveUserPreference = (theme: string) => {
    console.log(`Saving user preference: ${theme}`);
    if (storageAvailable) {
      try {
        localStorage.setItem(STORAGE_KEY, theme);
      } catch (e) {
        console.error("Failed to save user preference:", e);
      }
    }
  };

  // Function to determine system preference
  const getSystemPreference = (): string | null => {
    let preference = null;
    if (window.matchMedia) {
      if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
        preference = THEME_DARK;
      } else if (window.matchMedia("(prefers-color-scheme: light)").matches) {
        preference = THEME_LIGHT;
      }
    }
    return preference;
  };

  // **Added function to read default theme from HTML attribute**
  const getDefaultTheme = (): string => {
    const defaultTheme = root.getAttribute("data-theme") || THEME_DARK;
    return defaultTheme;
  };

  // Function to set theme based on preference
  const setTheme = () => {
    console.log("Setting theme");
    const userPreference = getUserPreference();
    console.log(`User preference in setTheme: ${userPreference}`);
    if (userPreference) {
      if (userPreference === THEME_SYSTEM) {
        const systemTheme = getSystemPreference() || getDefaultTheme();
        applyTheme(systemTheme);
      } else {
        applyTheme(userPreference);
      }
    } else {
      const systemPreference = getSystemPreference();
      if (systemPreference) {
        applyTheme(systemPreference);
      } else {
        const defaultTheme = getDefaultTheme();
        applyTheme(defaultTheme);
      }
    }
  };

  // Synchronize radio buttons with the applied theme
  const syncRadioButtons = () => {
    const selectedTheme = getUserPreference() || THEME_SYSTEM;
    const radio = document.querySelector(
      `input[name="theme"][value="${selectedTheme}"]`,
    ) as HTMLInputElement;
    if (radio) {
      radio.checked = true;
    } else {
    }
    console.log("Radio buttons after sync:");
  };

  // Apply theme and synchronize radio buttons immediately to prevent FOUC
  setTheme();
  syncRadioButtons();

  // Watch for system theme changes if user preference is 'system' or not set
  if (
    (!getUserPreference() || getUserPreference() === THEME_SYSTEM) &&
    window.matchMedia
  ) {
    const darkThemeMediaQuery = window.matchMedia(
      "(prefers-color-scheme: dark)",
    );

    const systemThemeChangeListener = (e: MediaQueryListEvent) => {
      if (!getUserPreference() || getUserPreference() === THEME_SYSTEM) {
        const newTheme = e.matches ? THEME_DARK : THEME_LIGHT;
        applyTheme(newTheme);
      }
    };

    if (darkThemeMediaQuery.addEventListener) {
      darkThemeMediaQuery.addEventListener("change", systemThemeChangeListener);
    } else if (darkThemeMediaQuery.addListener) {
      darkThemeMediaQuery.addListener(systemThemeChangeListener);
    }
  }

  // Handle theme selection via radio buttons
  const themeSwitcherForm = document.getElementById(
    "theme-switcher-form",
  ) as HTMLFormElement;

  if (themeSwitcherForm) {
    themeSwitcherForm.addEventListener("change", (event) => {
      const target = event.target as HTMLInputElement;
      if (target && target.name === "theme") {
        const selectedTheme = target.value;
        console.log(`Theme selected: ${selectedTheme}`);
        if ([THEME_LIGHT, THEME_DARK, THEME_SYSTEM].includes(selectedTheme)) {
          saveUserPreference(selectedTheme);
          setTheme();
          syncRadioButtons(); // Ensure radio buttons are synced
        }
      }
    });
  } else {
    console.warn("Theme switcher form not found");
  }
}
