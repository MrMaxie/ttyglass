<script lang="ts">
  import type { ColorScheme, ColorSchemeId } from './lib/color-schemes';
  import type { TerminalSize, TerminalSizingMode } from './lib/terminal';

  interface Props {
    schemes: readonly ColorScheme[];
    schemeId: ColorSchemeId;
    sizingMode: TerminalSizingMode;
    terminalSize: TerminalSize;
    onSchemeChange: (schemeId: ColorSchemeId) => void;
    onDynamicSize: () => void;
    onFixedSize: (size: TerminalSize) => void;
  }

  let {
    schemes,
    schemeId,
    sizingMode,
    terminalSize,
    onSchemeChange,
    onDynamicSize,
    onFixedSize,
  }: Props = $props();

  let columns = $state(0);
  let rows = $state(0);
  let draftInitialized = $state(false);
  let validationError = $state('');

  $effect(() => {
    if (!draftInitialized) {
      columns = terminalSize.cols;
      rows = terminalSize.rows;
      draftInitialized = true;
    }
  });

  function selectScheme(event: Event): void {
    onSchemeChange((event.currentTarget as HTMLSelectElement).value as ColorSchemeId);
  }

  function useDynamicSize(): void {
    validationError = '';
    onDynamicSize();
  }

  function useFixedSize(): void {
    columns = terminalSize.cols;
    rows = terminalSize.rows;
    validationError = '';
    onFixedSize({ cols: columns, rows });
  }

  function applyFixedSize(event: SubmitEvent): void {
    event.preventDefault();
    if (!Number.isInteger(columns) || columns < 2 || columns > 1000) {
      validationError = 'Columns must be a whole number from 2 to 1000.';
      return;
    }
    if (!Number.isInteger(rows) || rows < 1 || rows > 500) {
      validationError = 'Rows must be a whole number from 1 to 500.';
      return;
    }
    validationError = '';
    onFixedSize({ cols: columns, rows });
  }
</script>

<aside id="display-panel" class="display-panel" aria-labelledby="display-title">
  <header>
    <div>
      <h2 id="display-title">Display</h2>
      <p>Adjust this browser session.</p>
    </div>
  </header>

  <div class="display-content">
    <label class="field-label" for="color-scheme">TUI color scheme</label>
    <select id="color-scheme" value={schemeId} onchange={selectScheme}>
      {#each schemes as scheme}
        <option value={scheme.id}>{scheme.label}</option>
      {/each}
    </select>
    <p class="field-help">Maps ANSI, indexed, and truecolor output into the selected palette.</p>

    <fieldset>
      <legend>Terminal size</legend>
      <label class="choice-row">
        <input type="radio" name="terminal-size" checked={sizingMode === 'dynamic'} onchange={useDynamicSize} />
        <span>
          <strong>Dynamic</strong>
          <small>Follow the available browser space.</small>
        </span>
      </label>
      <label class="choice-row">
        <input type="radio" name="terminal-size" checked={sizingMode === 'fixed'} onchange={useFixedSize} />
        <span>
          <strong>Fixed</strong>
          <small>Keep exact columns and rows.</small>
        </span>
      </label>
    </fieldset>

    {#if sizingMode === 'fixed'}
      <form class="size-form" novalidate onsubmit={applyFixedSize}>
        <label>
          <span>Columns</span>
          <input type="number" min="2" max="1000" step="1" bind:value={columns} aria-describedby="size-error" />
        </label>
        <label>
          <span>Rows</span>
          <input type="number" min="1" max="500" step="1" bind:value={rows} aria-describedby="size-error" />
        </label>
        <button type="submit">Apply size</button>
      </form>
      <p id="size-error" class="validation-message" aria-live="polite">{validationError}</p>
    {:else}
      <p class="current-size">Current size: {terminalSize.cols} x {terminalSize.rows}</p>
    {/if}
  </div>
</aside>
