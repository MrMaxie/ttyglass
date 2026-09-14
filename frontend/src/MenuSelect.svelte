<script lang="ts">
  import { onMount, tick } from 'svelte';

  interface MenuOption {
    value: string;
    label: string;
    description?: string;
    state?: string;
    title?: string;
  }

  interface Props {
    ariaLabel: string;
    disabled?: boolean;
    onChange: (value: string) => void;
    options: readonly MenuOption[];
    placeholder: string;
    title?: string;
    value: string;
  }

  let { ariaLabel, disabled = false, onChange, options, placeholder, title, value }: Props = $props();
  let container: HTMLDivElement;
  let trigger: HTMLButtonElement;
  let menu = $state<HTMLDivElement>();
  let expanded = $state(false);
  let menuStyle = $state('');
  const selected = $derived(options.find((option) => option.value === value));

  function optionElements(): HTMLButtonElement[] {
    return Array.from(container.querySelectorAll<HTMLButtonElement>('[role="option"]'));
  }

  function positionMenu(): void {
    if (!expanded || menu === undefined) return;
    const triggerBounds = trigger.getBoundingClientRect();
    const gap = 6;
    const viewportMargin = 8;
    const viewportMaximum = Math.min(320, window.innerHeight * 0.6);
    const menuHeight = Math.min(menu.scrollHeight, viewportMaximum);
    const spaceBelow = window.innerHeight - triggerBounds.bottom - gap - viewportMargin;
    const spaceAbove = triggerBounds.top - gap - viewportMargin;
    const opensAbove = spaceBelow < menuHeight && spaceAbove > spaceBelow;
    const availableHeight = Math.max(80, opensAbove ? spaceAbove : spaceBelow);
    const width = Math.min(triggerBounds.width, window.innerWidth - viewportMargin * 2);
    const left = Math.min(Math.max(triggerBounds.left, viewportMargin), window.innerWidth - width - viewportMargin);
    const top = opensAbove
      ? Math.max(viewportMargin, triggerBounds.top - gap - Math.min(menuHeight, availableHeight))
      : triggerBounds.bottom + gap;
    menuStyle = `left: ${left}px; top: ${top}px; width: ${width}px; max-height: ${Math.min(viewportMaximum, availableHeight)}px`;
  }

  async function openAt(index: number): Promise<void> {
    if (disabled || options.length === 0) return;
    expanded = true;
    await tick();
    positionMenu();
    const elements = optionElements();
    elements[Math.max(0, Math.min(index, elements.length - 1))]?.focus();
  }

  async function toggle(): Promise<void> {
    if (disabled || options.length === 0) return;
    expanded = !expanded;
    if (expanded) {
      await tick();
      positionMenu();
    }
  }

  function choose(option: MenuOption): void {
    expanded = false;
    onChange(option.value);
    trigger.focus();
  }

  function handleTriggerKey(event: KeyboardEvent): void {
    const selectedIndex = Math.max(0, options.findIndex((option) => option.value === value));
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      void openAt(selectedIndex);
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      void openAt(selectedIndex);
    }
  }

  function handleMenuKey(event: KeyboardEvent): void {
    const elements = optionElements();
    const currentIndex = elements.indexOf(event.target as HTMLButtonElement);
    if (event.key === 'Escape') {
      event.preventDefault();
      expanded = false;
      trigger.focus();
    } else if (event.key === 'ArrowDown') {
      event.preventDefault();
      elements[(currentIndex + 1) % elements.length]?.focus();
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      elements[(currentIndex - 1 + elements.length) % elements.length]?.focus();
    } else if (event.key === 'Home') {
      event.preventDefault();
      elements[0]?.focus();
    } else if (event.key === 'End') {
      event.preventDefault();
      elements.at(-1)?.focus();
    }
  }

  function handleFocusOut(event: FocusEvent): void {
    if (event.relatedTarget instanceof Node && container.contains(event.relatedTarget)) return;
    expanded = false;
  }

  onMount(() => {
    const closeOutside = (event: PointerEvent): void => {
      if (event.target instanceof Node && !container.contains(event.target)) expanded = false;
    };
    const reposition = (): void => positionMenu();
    document.addEventListener('pointerdown', closeOutside);
    window.addEventListener('resize', reposition);
    window.addEventListener('scroll', reposition, true);
    return () => {
      document.removeEventListener('pointerdown', closeOutside);
      window.removeEventListener('resize', reposition);
      window.removeEventListener('scroll', reposition, true);
    };
  });
</script>

<div class="menu-select" bind:this={container} onfocusout={handleFocusOut}>
  <button
    bind:this={trigger}
    type="button"
    class="menu-select-trigger"
    aria-label={ariaLabel}
    aria-haspopup="listbox"
    aria-expanded={expanded}
    {disabled}
    {title}
    onclick={() => void toggle()}
    onkeydown={handleTriggerKey}
  >
    <span>{selected?.label ?? placeholder}</span>
    <span class="menu-select-chevron" aria-hidden="true"></span>
  </button>
  {#if expanded}
    <div
      bind:this={menu}
      class="menu-select-menu"
      role="listbox"
      aria-label={ariaLabel}
      tabindex="-1"
      style={menuStyle}
      onkeydown={handleMenuKey}
    >
      {#each options as option}
        <button
          type="button"
          class="menu-select-option"
          role="option"
          aria-selected={option.value === value}
          title={option.title}
          onclick={() => choose(option)}
        >
          <span class="menu-select-copy">
            <strong>{option.label}</strong>
            {#if option.description}<small>{option.description}</small>{/if}
          </span>
          {#if option.state}
            <span class="menu-select-state"><span class="status-dot" data-state={option.state}></span>{option.state}</span>
          {/if}
        </button>
      {/each}
    </div>
  {/if}
</div>
