<script>
  import { ChevronUp, ChevronDown } from "lucide-svelte";
  import { createEventDispatcher } from "svelte";
  import { clickOutsideAction } from "svelte-tel-input/utils";
  import { TelInput, isSelected, normalizedCountries } from "svelte-tel-input";
  import "svelte-tel-input/styles/flags.css";

  /**
   * @typedef {Object} Props
   * @property {boolean} [clickOutside]
   * @property {boolean} [closeOnClick]
   * @property {boolean} [disabled]
   * @property {any} [detailedValue]
   * @property {any} value
   * @property {string} [searchPlaceholder]
   * @property {string} [selectedCountry]
   * @property {any} valid
   * @property {any} [options]
   * @property {string} [placeholder]
   * @property {any} inputClass
   * @property {any} cls
   * @property {import('svelte').Snippet} [children]
   */

  /** @type {Props} */
  let {
    clickOutside = true,
    closeOnClick = true,
    disabled = false,
    detailedValue = $bindable(null),
    value = $bindable(),
    searchPlaceholder = "Search country codes...",
    selectedCountry = $bindable("CA"),
    valid = $bindable(),
    options = { format: "national", autoPlaceholder: false },
    placeholder = "Your phone number",
    inputClass,
    countryClass,
    class: cls,
    children,
  } = $props();

  let searchText = $state("");
  let isOpen = $state(false);

  let selectedCountryDialCode = $derived(
    normalizedCountries.find((el) => el.iso2 === selectedCountry)?.dialCode ||
      null
  );

  const toggleDropDown = (e) => {
    e?.preventDefault();
    if (disabled) return;
    isOpen = !isOpen;
  };

  const closeDropdown = (e) => {
    if (isOpen) {
      e?.preventDefault();
      isOpen = false;
      searchText = "";
    }
  };

  const selectClick = () => {
    if (closeOnClick) closeDropdown();
  };

  const closeOnClickOutside = () => {
    if (clickOutside) {
      closeDropdown();
    }
  };

  const sortCountries = (countries, text) => {
    const normalizedText = text.trim().toLowerCase();
    if (!normalizedText) {
      return countries.sort((a, b) => a.label.localeCompare(b.label));
    }
    return countries.sort((a, b) => {
      const aNameLower = a.name.toLowerCase();
      const bNameLower = b.name.toLowerCase();
      const aStartsWith = aNameLower.startsWith(normalizedText);
      const bStartsWith = bNameLower.startsWith(normalizedText);
      if (aStartsWith && !bStartsWith) return -1;
      if (!aStartsWith && bStartsWith) return 1;
      const aIndex = aNameLower.indexOf(normalizedText);
      const bIndex = bNameLower.indexOf(normalizedText);
      if (aIndex === -1 && bIndex === -1) return a.id.localeCompare(b.id);
      if (aIndex === -1) return 1;
      if (bIndex === -1) return -1;
      const aWeight = aIndex + (aStartsWith ? 0 : 1);
      const bWeight = bIndex + (bStartsWith ? 0 : 1);
      return aWeight - bWeight;
    });
  };

  const handleSelect = (val, e) => {
    if (disabled) return;
    e?.preventDefault();
    if (
      selectedCountry === undefined ||
      selectedCountry === null ||
      (typeof selectedCountry === typeof val && selectedCountry !== val)
    ) {
      selectedCountry = val;
      onChange(val);
      selectClick();
    } else {
      dispatch("same", { option: val });
      selectClick();
    }
  };

  const dispatch = createEventDispatcher();

  const onChange = (selectedCountry) => {
    dispatch("change", { option: selectedCountry });
  };
</script>

<div
  class="grow flex relative rounded-lg {valid
    ? ``
    : ` ring-error dark:ring-error ring-1 focus-within:ring-offset-1 focus-within:ring-offset-error/50 focus-within:ring-1`}"
>
  <div class="flex" use:clickOutsideAction={closeOnClickOutside}>
    <button
      id="states-button"
      data-dropdown-toggle="dropdown-states"
      class={[
        "relative flex-shrink-0 overflow-hidden z-10 whitespace-nowrap",
        "inline-flex items-center p-1.5 pl-3 text-sm font-medium text-center",
        "text-gray-500 bg-base-100 rounded-l-lg",
        "hover:bg-base-200 focus:outline-none",
        "dark:text-white",
        countryClass,
      ].join(" ")}
      type="button"
      role="combobox"
      aria-controls="dropdown-countries"
      aria-expanded="false"
      aria-haspopup="false"
      onclick={toggleDropDown}
    >
      {#if selectedCountry && selectedCountry !== null}
        <div class="inline-flex items-center text-left">
          <span
            class="flag flag-{selectedCountry.toLowerCase()} flex-shrink-0 mr-1.5"
          ></span>
          {#if options?.format === "national"}
            <span class=" text-gray-600 dark:text-gray-400"
              >+{selectedCountryDialCode}</span
            >
          {/if}
        </div>
      {:else}
        Please select
      {/if}
    </button>
    {#if isOpen}
      <div
        id="dropdown-countries"
        class="absolute z-20 max-w-fit rounded divide-y divide-gray-100 shadow bg-base-100 overflow-hidden translate-y-11"
        data-popper-reference-hidden=""
        data-popper-escaped=""
        data-popper-placement="bottom"
        aria-orientation="vertical"
        aria-labelledby="country-button"
        tabindex="-1"
      >
        <div
          class="text-sm text-gray-700 dark:text-gray-200 max-h-48 overflow-y-auto"
          aria-labelledby="countries-button"
          role="listbox"
        >
          <input
            aria-autocomplete="list"
            type="text"
            class="px-4 py-2 text-gray-900 focus:outline-none w-full sticky top-0"
            bind:value={searchText}
            placeholder={searchPlaceholder}
          />
          {#each sortCountries(normalizedCountries, searchText) as country (country.id)}
            {@const isActive = isSelected(country.iso2, selectedCountry)}
            <div
              id="country-{country.iso2}"
              role="option"
              aria-selected={isActive}
            >
              <button
                value={country.iso2}
                type="button"
                class="inline-flex py-2 px-4 w-full text-sm hover:bg-gray-100 dark:hover:bg-gray-600
                             active:bg-gray-800 dark:active:bg-gray-800 overflow-hidden
                            {isActive
                  ? 'bg-gray-600 dark:text-white'
                  : 'dark:hover:text-white dark:text-gray-400'}"
                onclick={(e) => {
                  handleSelect(country.iso2, e);
                }}
              >
                <div class="inline-flex items-center text-left">
                  <span
                    class="flag flag-{country.iso2.toLowerCase()} flex-shrink-0 mr-3"
                  ></span>
                  <span class="mr-2">{country.name}</span>
                  <span class="text-gray-500">+{country.dialCode}</span>
                </div>
              </button>
            </div>
          {/each}
        </div>
      </div>
    {/if}
  </div>

  <div
    class={`text-base rounded-r-lg block w-full p-1.5
      focus:outline-none bg-base-100 dark:text-white text-gray-900 flex items-center gap-2 ${cls}`}
  >
    <TelInput
      {placeholder}
      bind:country={selectedCountry}
      bind:detailedValue
      bind:value
      bind:valid
      {options}
      {disabled}
      class="p-0 bg-transparent focus:outline-none placeholder:text-sm w-full input-sm"
    />

    {@render children?.()}
  </div>
</div>
