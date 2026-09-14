<script lang="ts">
  import { onMount } from 'svelte';

  import DiagnosticsPanel from './DiagnosticsPanel.svelte';
  import DisplayPanel from './DisplayPanel.svelte';
  import { type ColorSchemeId, colorSchemes, findColorScheme } from './lib/color-schemes';
  import type { DiagnosticEntry } from './lib/diagnostics';
  import { sessionLabel } from './lib/session-label';
  import type { TerminalController, TerminalMessage, TerminalSize, TerminalSizingMode } from './lib/terminal';
  import MenuSelect from './MenuSelect.svelte';
  import TerminalPane from './TerminalPane.svelte';

  interface ProcessStatus {
    state: string;
    label: string;
    pid: number | undefined;
    restartable: boolean;
  }

  interface SessionSummary {
    sessionId: string;
    name: string;
    displayCommand: string;
    status: string;
    pid: number;
    url: string;
  }

  type ClientMessage = TerminalMessage | { type: 'restart'; cols: number; rows: number } | { type: 'clearLogs' };

  function readToken(): string | null {
    const hashParameters = new URLSearchParams(location.hash.slice(1));
    const hashToken = hashParameters.get('token');
    if (hashToken !== null) {
      sessionStorage.setItem(`ttyglass.token.${location.pathname}`, hashToken);
      history.replaceState(null, '', `${location.pathname}${location.search}`);
      return hashToken;
    }
    return sessionStorage.getItem(`ttyglass.token.${location.pathname}`);
  }

  const sessionMatch = location.pathname.match(/^\/sessions\/([^/]+)$/);
  const sessionId = sessionMatch?.[1] ?? null;
  const listMode = sessionId === null;
  const routeToken = readToken();
  if (listMode && routeToken !== null) sessionStorage.setItem('ttyglass.managementToken', routeToken);
  const managementToken = listMode ? routeToken : sessionStorage.getItem('ttyglass.managementToken');
  const token = listMode ? null : routeToken;
  const version = __TTYGLASS_VERSION__;
  let command = $state('No command');
  let sessionName = $state('');
  let diagnosticsOpen = $state(false);
  let displayOpen = $state(false);
  let diagnostics = $state<DiagnosticEntry[]>([]);
  let sessions = $state<SessionSummary[]>([]);
  let listError = $state('');
  let listLoading = $state(listMode);
  let colorSchemeId = $state<ColorSchemeId>('default');
  let sizingMode = $state<TerminalSizingMode>('dynamic');
  let terminalSize = $state<TerminalSize>({ cols: 100, rows: 30 });
  let metadataRestartable = $state(false);
  let processStatus = $state<ProcessStatus>({ state: 'connecting', label: 'Connecting', pid: undefined, restartable: false });
  let socket: WebSocket | undefined;
  let terminal = $state<TerminalController | undefined>();
  const sessionOptions = $derived(
    sessions.map((session) => ({
      value: session.sessionId,
      label: sessionLabel(session.name, session.displayCommand),
      state: session.status,
      title: session.displayCommand,
    })),
  );
  const visibleSessionOptions = $derived(
    sessionId !== null && !sessionOptions.some((option) => option.value === sessionId)
      ? [{ value: sessionId, label: sessionLabel(sessionName, command), title: command }, ...sessionOptions]
      : sessionOptions,
  );

  function setStatus(state: string, pid?: number, exitCode?: number): void {
    if (state === 'running') {
      processStatus = { state, label: 'Running', pid, restartable: metadataRestartable };
    } else if (state === 'exited') {
      processStatus = { state, label: `Exited (${exitCode ?? 'unknown'})`, pid, restartable: metadataRestartable };
    } else if (state === 'failed') {
      processStatus = { state, label: 'Failed to start', pid: undefined, restartable: metadataRestartable };
    } else if (state === 'stopped') {
      processStatus = { state, label: 'Stopped', pid: undefined, restartable: metadataRestartable };
    } else {
      processStatus = { state: state.toLowerCase().replaceAll(' ', '-'), label: state, pid: undefined, restartable: false };
    }
  }

  function send(message: ClientMessage): boolean {
    if (socket?.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(message));
      return true;
    }
    return false;
  }

  function handleServerMessage(event: MessageEvent): void {
    let message: Record<string, unknown>;
    try {
      const parsed = JSON.parse(String(event.data)) as unknown;
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) return;
      message = parsed as Record<string, unknown>;
    } catch {
      return;
    }

    if (message.type === 'output' && typeof message.data === 'string') {
      terminal?.write(message.data);
    } else if (message.type === 'status' && typeof message.state === 'string') {
      setStatus(message.state, typeof message.pid === 'number' ? message.pid : undefined, typeof message.exitCode === 'number' ? message.exitCode : undefined);
    } else if (message.type === 'metadata' && typeof message.displayCommand === 'string') {
      command = message.displayCommand;
      sessionName = typeof message.name === 'string' ? message.name : '';
      metadataRestartable = message.restartable === true;
      processStatus = { ...processStatus, restartable: metadataRestartable };
      document.title = `${message.displayCommand} - ttyglass`;
    } else if (message.type === 'log' && typeof message.entry === 'object' && message.entry !== null) {
      diagnostics = [...diagnostics, message.entry as DiagnosticEntry].slice(-500);
    } else if (message.type === 'logs' && Array.isArray(message.entries)) {
      diagnostics = (message.entries as DiagnosticEntry[]).slice(-500);
    } else if (message.type === 'logsCleared') {
      diagnostics = [];
    }
  }

  async function loadSessions(openDefault = false): Promise<void> {
    if (managementToken === null) {
      if (listMode) listError = 'Missing management token. Open the exact URL printed by ttyglass serve or ttyglass open.';
      listLoading = false;
      return;
    }
    try {
      const response = await fetch('/api/sessions', { headers: { Authorization: `Bearer ${managementToken}` } });
      if (!response.ok) throw new Error(response.status === 401 ? 'The management token is invalid.' : `Request failed with ${response.status}.`);
      const loadedSessions = (await response.json()) as SessionSummary[];
      sessions = loadedSessions;
      listError = '';
      if (openDefault && loadedSessions.length > 0) {
        const previousSessionId = sessionStorage.getItem('ttyglass.selectedSession');
        const selectedSession = loadedSessions.find((session) => session.sessionId === previousSessionId) ?? loadedSessions[0];
        if (selectedSession !== undefined) location.replace(selectedSession.url);
      }
    } catch (error) {
      listError = error instanceof Error ? error.message : 'Could not load ttyglass sessions.';
    } finally {
      listLoading = false;
    }
  }

  function selectSession(selectedSessionId: string): void {
    const selectedSession = sessions.find((session) => session.sessionId === selectedSessionId);
    if (selectedSession === undefined || selectedSession.sessionId === sessionId) return;
    sessionStorage.setItem('ttyglass.selectedSession', selectedSession.sessionId);
    location.assign(selectedSession.url);
  }

  function connect(): void {
    if (token === null || sessionId === null) {
      setStatus('Missing session token');
      return;
    }
    const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
    socket = new WebSocket(`${protocol}//${location.host}/terminal?session=${encodeURIComponent(sessionId)}&token=${encodeURIComponent(token)}`);
    socket.addEventListener('open', () => {
      setStatus('Connected');
      requestAnimationFrame(() => {
        terminal?.fit();
        terminal?.focus();
      });
    });
    socket.addEventListener('message', handleServerMessage);
    socket.addEventListener('close', () => setStatus('Disconnected'));
    socket.addEventListener('error', () => setStatus('Connection error'));
  }

  function handleTerminalReady(controller: TerminalController | undefined): void {
    terminal = controller;
    if (controller !== undefined && token === null) controller.writeln('\r\nTTYGlass could not authenticate this tab. Open the exact URL printed by the CLI.');
  }

  function handleSchemeChange(nextSchemeId: ColorSchemeId): void {
    colorSchemeId = nextSchemeId;
    terminal?.setColorScheme(findColorScheme(nextSchemeId));
  }

  function useDynamicSize(): void {
    sizingMode = 'dynamic';
    terminal?.setDynamicSize();
  }

  function useFixedSize(size: TerminalSize): void {
    sizingMode = 'fixed';
    terminal?.setFixedSize(size);
  }

  function restart(): void {
    if (terminal === undefined || !metadataRestartable) return;
    terminal.reset();
    setStatus('Restarting');
    send({ type: 'restart', ...terminal.size() });
    terminal.focus();
  }

  function toggleDiagnostics(): void {
    diagnosticsOpen = !diagnosticsOpen;
    if (diagnosticsOpen) displayOpen = false;
  }

  function toggleDisplay(): void {
    displayOpen = !displayOpen;
    if (displayOpen) diagnosticsOpen = false;
  }

  function closePanels(event: KeyboardEvent): void {
    if (event.key === 'Escape') {
      diagnosticsOpen = false;
      displayOpen = false;
    }
  }

  async function copyCommand(): Promise<void> {
    await navigator.clipboard.writeText(command);
  }

  onMount(() => {
    if (listMode) {
      void loadSessions(true);
      const timer = window.setInterval(() => void loadSessions(true), 2_000);
      return () => window.clearInterval(timer);
    }
    void loadSessions();
    const sessionTimer = window.setInterval(() => void loadSessions(), 2_000);
    const closeSocket = (): void => socket?.close();
    window.addEventListener('beforeunload', closeSocket);
    connect();
    return () => {
      window.clearInterval(sessionTimer);
      window.removeEventListener('beforeunload', closeSocket);
      socket?.close();
    };
  });
</script>

<svelte:window onkeydown={closePanels} />

{#if listMode}
  <main class="shell empty-shell">
    <header class="toolbar">
      <div class="identity">
        <img src="/ttyglass-logo.svg" alt="" width="24" height="24" />
        <div><strong class="product-name">TTYGLASS</strong><span class="product-version">v{version}</span></div>
      </div>
      <div class="session-picker">
        <MenuSelect
          ariaLabel="Session"
          value=""
          options={[]}
          placeholder={listLoading ? 'Loading sessions...' : 'No sessions'}
          disabled
          onChange={() => undefined}
        />
      </div>
    </header>
    <section class="empty-session" aria-live="polite">
      {#if listError}
        <div class="empty-session-content" role="alert"><strong>Sessions unavailable</strong><p>{listError}</p></div>
      {:else if !listLoading}
        <div class="empty-session-content">
          <strong>No sessions</strong>
          <p>Start a terminal or command session from another shell.</p>
          <code>ttyglass start --name "Terminal"</code>
          <code>ttyglass start --name "App" -- npm run tui</code>
        </div>
      {/if}
    </section>
  </main>
{:else}
  <main class="shell" class:diagnostics-open={diagnosticsOpen}>
    <header class="toolbar">
      <div class="identity">
        <a class="identity-link" href="/" aria-label="Open default session"><img src="/ttyglass-logo.svg" alt="" width="24" height="24" /></a>
        <div><strong class="product-name">TTYGLASS</strong><span class="product-version">v{version}</span></div>
      </div>
      <div class="session-picker">
        <MenuSelect
          ariaLabel="Session"
          value={sessionId}
          options={visibleSessionOptions}
          placeholder={sessionLabel(sessionName, command)}
          title={command}
          onChange={(value) => selectSession(value)}
        />
      </div>
      <div class="process-state" aria-live="polite">
        <span class="status-dot" data-state={processStatus.state}></span><span>{processStatus.label}</span>
        {#if processStatus.pid !== undefined}<span class="pid">PID {processStatus.pid}</span>{/if}
      </div>
      <div class="toolbar-actions">
        <button type="button" class="secondary copy-command" title="Copy full command" onclick={() => void copyCommand()}>Copy</button>
        {#if metadataRestartable}
          <button type="button" class="secondary" disabled={!processStatus.restartable || terminal === undefined} onclick={restart}>Restart</button>
        {/if}
        <button type="button" class="secondary" aria-expanded={displayOpen} aria-controls="display-panel" onclick={toggleDisplay}>Display</button>
        <button type="button" class="secondary" aria-expanded={diagnosticsOpen} aria-controls="diagnostics" onclick={toggleDiagnostics}>Diagnostics</button>
      </div>
    </header>
    <section class="terminal-panel" class:fixed-terminal={sizingMode === 'fixed'} aria-label="Observed terminal">
      <TerminalPane onReady={handleTerminalReady} onSize={(size) => (terminalSize = size)} scheme={findColorScheme(colorSchemeId)} {send} />
    </section>
    {#if displayOpen}
      <DisplayPanel schemes={colorSchemes} schemeId={colorSchemeId} {sizingMode} {terminalSize} onSchemeChange={handleSchemeChange} onDynamicSize={useDynamicSize} onFixedSize={useFixedSize} />
    {/if}
    {#if diagnosticsOpen}<DiagnosticsPanel entries={diagnostics} onClear={() => send({ type: 'clearLogs' })} />{/if}
  </main>
{/if}
