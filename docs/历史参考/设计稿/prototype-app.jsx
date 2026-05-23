// Prototype shell — full macOS desktop with:
// - menu bar containing our cc-bar item (clickable)
// - floating HUD (draggable, toggleable)
// - statistics window + preferences window (openable)
// - dark / light theme toggle
// - tweaks panel for variant switching

const PROTO_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "menubarVariant": "icon-percent",
  "popoverVariant": "vertical-list",
  "hudVariant": "two-row-pill",
  "showHud": true,
  "hudPos": "topRight",
  "openWindow": "none",
  "popoverOpen": true
}/*EDITMODE-END*/;

function PrototypeApp() {
  const [t, setTweak] = useTweaks(PROTO_DEFAULTS);
  const theme = t.theme;
  const isDark = theme === 'dark';
  const wallpaper = isDark ? MAC_WALLPAPERS.dark : MAC_WALLPAPERS.light;
  const containerRef = React.useRef(null);
  const [hudOffset, setHudOffset] = React.useState({ x: 0, y: 0 });

  // close popover on outside click
  React.useEffect(() => {
    if (!t.popoverOpen) return;
    const onDown = (e) => {
      if (!e.target.closest('[data-popover]') && !e.target.closest('[data-menubar-trigger]')) {
        setTweak('popoverOpen', false);
      }
    };
    setTimeout(() => document.addEventListener('pointerdown', onDown), 0);
    return () => document.removeEventListener('pointerdown', onDown);
  }, [t.popoverOpen]);

  return (
    <div className={'theme-' + theme} ref={containerRef} style={{
      position: 'fixed', inset: 0,
      background: wallpaper,
      backgroundSize: 'cover',
      fontFamily: 'var(--font-sf)',
      color: 'var(--text-primary)',
      overflow: 'hidden',
    }}>
      {/* Menu Bar */}
      <ProtoMenuBar
        theme={theme}
        variant={t.menubarVariant}
        onClickApp={() => setTweak('popoverOpen', !t.popoverOpen)}
        onOpenStats={() => setTweak('openWindow', 'stats')}
        onOpenPrefs={() => setTweak('openWindow', 'prefs')}
      />

      {/* Popover */}
      {t.popoverOpen && (
        <div data-popover style={{
          position: 'absolute',
          top: 34,
          right: 120,
          zIndex: 1000,
          animation: 'popIn 0.18s cubic-bezier(0.2, 0.9, 0.3, 1.15)',
        }}>
          <PopoverByVariant variant={t.popoverVariant} theme={theme}
            onOpenStats={() => { setTweak('openWindow', 'stats'); setTweak('popoverOpen', false); }}
            onOpenPrefs={() => { setTweak('openWindow', 'prefs'); setTweak('popoverOpen', false); }}/>
        </div>
      )}

      {/* HUD */}
      {t.showHud && (
        <DraggableHUD
          theme={theme}
          variant={t.hudVariant}
          initialPos={t.hudPos}
          containerRef={containerRef}
        />
      )}

      {/* Windows */}
      {t.openWindow === 'stats' && (
        <ProtoWindow onClose={() => setTweak('openWindow', 'none')} initial={{x: 80, y: 70, w: 1040, h: 620}}>
          <StatsV_Dashboard theme={theme}/>
        </ProtoWindow>
      )}
      {t.openWindow === 'prefs' && (
        <ProtoWindow onClose={() => setTweak('openWindow', 'none')} initial={{x: 200, y: 80, w: 680, h: 640}}>
          <PrefsV_Main theme={theme}/>
        </ProtoWindow>
      )}

      {/* Dock hint */}
      <DockHint/>

      {/* Hint overlay when nothing's open */}
      {!t.popoverOpen && t.openWindow === 'none' && <FirstHint theme={theme}/>}

      {/* Tweaks panel */}
      <TweaksPanel>
        <TweakSection label="System · 系统"/>
        <TweakRadio label="Theme · 主题" value={t.theme} options={['dark', 'light']} onChange={v => setTweak('theme', v)}/>
        <TweakSection label="Menu bar · 菜单栏"/>
        <TweakSelect label="Icon variant" value={t.menubarVariant}
          options={[
            { value: 'icon-only', label: 'Icon only' },
            { value: 'icon-percent', label: 'Icon + %' },
            { value: 'two-pills', label: 'Two pills (C / CC)' },
            { value: 'ring-percent', label: 'Ring + %' },
            { value: 'dual-bars', label: 'Dual bars' },
            { value: 'text-only', label: 'Text only' },
            { value: 'state-color', label: 'State color (low %)' },
            { value: 'weekly-mode', label: '5h ↔ Weekly' },
          ]}
          onChange={v => setTweak('menubarVariant', v)}/>
        <TweakSection label="Popover · 弹出面板"/>
        <TweakSelect label="Layout" value={t.popoverVariant}
          options={[
            { value: 'vertical-list', label: 'A · Vertical list' },
            { value: 'dense-compact', label: 'B · Dense compact' },
            { value: 'spark-chart', label: 'C · Spark chart' },
            { value: 'big-stat', label: 'D · Big stat' },
          ]}
          onChange={v => setTweak('popoverVariant', v)}/>
        <TweakButton onClick={() => setTweak('popoverOpen', !t.popoverOpen)}>
          {t.popoverOpen ? 'Close popover' : 'Open popover'}
        </TweakButton>
        <TweakSection label="Floating HUD · 悬浮窗"/>
        <TweakToggle label="Show HUD" value={t.showHud} onChange={v => setTweak('showHud', v)}/>
        <TweakSelect label="Style" value={t.hudVariant}
          options={[
            { value: 'two-row-pill', label: 'Two-row pill' },
            { value: 'stacked-numbers', label: 'Stacked numbers' },
            { value: 'dual-rings', label: 'Dual rings' },
            { value: 'ultra-thin', label: 'Ultra-thin' },
            { value: 'single-service', label: 'Single service' },
            { value: 'horizontal-slim', label: 'Horizontal slim' },
            { value: 'five-hour-week', label: '5h + Weekly' },
            { value: 'no-chrome', label: 'No chrome' },
          ]}
          onChange={v => setTweak('hudVariant', v)}/>
        <TweakSection label="Windows · 窗口"/>
        <TweakRadio label="Open" value={t.openWindow}
          options={['none', 'stats', 'prefs']}
          onChange={v => setTweak('openWindow', v)}/>
      </TweaksPanel>
    </div>
  );
}

// Menu bar with multiple icon-variant renderers ------------------------------
function ProtoMenuBar({ theme, variant, onClickApp, onOpenStats, onOpenPrefs }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      height: 30, zIndex: 500,
      backdropFilter: 'saturate(140%) blur(20px)',
      WebkitBackdropFilter: 'saturate(140%) blur(20px)',
      background: isDark ? 'rgba(20,20,22,0.42)' : 'rgba(255,255,255,0.32)',
      borderBottom: isDark ? '0.5px solid rgba(255,255,255,0.06)' : '0.5px solid rgba(0,0,0,0.06)',
      display: 'flex', alignItems: 'center',
      paddingLeft: 14, paddingRight: 14,
      fontSize: 13, letterSpacing: -0.08,
      color: isDark ? '#F5F5F7' : '#1D1D1F',
    }}>
      <svg width="13" height="15" viewBox="0 0 14 16" fill="currentColor" style={{marginRight: 16, opacity: 0.95}}>
        <path d="M11.182 8.34c-.02-2.069 1.687-3.063 1.763-3.111-.96-1.405-2.456-1.597-2.99-1.62-1.272-.129-2.485.749-3.132.749-.648 0-1.647-.73-2.706-.71-1.394.022-2.679.809-3.395 2.054-1.448 2.508-.371 6.221 1.039 8.26.685.998 1.503 2.119 2.578 2.079 1.034-.041 1.426-.668 2.676-.668 1.249 0 1.602.668 2.7.65 1.114-.02 1.821-1.018 2.502-2.019.787-1.158 1.114-2.282 1.135-2.34-.025-.011-2.168-.832-2.189-3.323zM9.085 2.298C9.66 1.604 10.046.628 9.94-.343c-.835.034-1.844.555-2.435 1.247-.532.616-.997 1.602-.872 2.555.929.072 1.878-.471 2.452-1.161z"/>
      </svg>
      <span style={{fontWeight: 600, marginRight: 20}}>cc-bar</span>
      <span style={{marginRight: 16, opacity: 0.85}} onClick={onOpenStats}>File</span>
      <span style={{marginRight: 16, opacity: 0.85}} onClick={onOpenPrefs}>Edit</span>
      <span style={{marginRight: 16, opacity: 0.85}}>View</span>
      <span style={{opacity: 0.85}}>Window</span>

      <div style={{marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 14}}>
        {/* Our app's menu bar item */}
        <button
          data-menubar-trigger
          onClick={onClickApp}
          style={{
            display: 'inline-flex', alignItems: 'center', gap: 6,
            height: 22, padding: '0 7px',
            borderRadius: 5, border: 0, background: 'transparent',
            color: 'inherit', fontFamily: 'inherit', fontSize: 12.5,
            cursor: 'default',
            transition: 'background 0.1s',
          }}
          onMouseEnter={e => e.currentTarget.style.background = isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.06)'}
          onMouseLeave={e => e.currentTarget.style.background = 'transparent'}>
          {renderMenubarVariant(variant, theme)}
        </button>

        <svg width="26" height="12" viewBox="0 0 26 12" fill="none" style={{opacity: 0.9}}>
          <rect x="0.5" y="0.5" width="22" height="11" rx="3" stroke="currentColor" strokeOpacity="0.5"/>
          <rect x="2" y="2" width="14" height="8" rx="1.5" fill="currentColor" fillOpacity="0.95"/>
          <rect x="23.5" y="3.5" width="2" height="5" rx="1" fill="currentColor" fillOpacity="0.5"/>
        </svg>
        <svg width="15" height="11" viewBox="0 0 15 11" fill="currentColor" style={{opacity: 0.95}}>
          <path d="M7.5 0C4.7 0 2.1 1 .1 2.7l1.2 1.4C3 2.7 5.2 1.8 7.5 1.8s4.5.9 6.2 2.3l1.2-1.4C12.9 1 10.3 0 7.5 0zm0 3.6c-1.9 0-3.7.7-5.1 1.9l1.2 1.4c1.1-.9 2.4-1.5 3.9-1.5s2.9.5 3.9 1.5l1.2-1.4c-1.4-1.2-3.2-1.9-5.1-1.9zm0 3.6c-1 0-1.9.4-2.6 1l1.2 1.4c.4-.4 1-.6 1.4-.6s1 .2 1.4.6l1.2-1.4c-.7-.6-1.6-1-2.6-1z"/>
        </svg>
        <span style={{fontSize: 13, fontVariantNumeric: 'tabular-nums'}}>Tue 22 May 14:42</span>
      </div>
    </div>
  );
}

function renderMenubarVariant(v, theme) {
  const isDark = theme === 'dark';
  switch (v) {
    case 'icon-only': return <AppGlyph size={14}/>;
    case 'icon-percent': return <><AppGlyph size={14}/><span style={{fontWeight: 500}}>62%</span></>;
    case 'two-pills': return <>
      <span style={{display: 'inline-flex', alignItems: 'center', gap: 3, padding: '2px 5px', borderRadius: 4,
        background: isDark ? 'rgba(152,152,157,0.26)' : 'rgba(108,108,112,0.2)',
        fontSize: 11, fontWeight: 600, letterSpacing: -0.1}}>C 42%</span>
      <span style={{display: 'inline-flex', alignItems: 'center', gap: 3, padding: '2px 5px', borderRadius: 4,
        background: isDark ? 'rgba(230,138,110,0.3)' : 'rgba(217,119,87,0.24)',
        fontSize: 11, fontWeight: 600, letterSpacing: -0.1}}>CC 78%</span>
    </>;
    case 'ring-percent': return <><Ring size={14} stroke={2.2} value={0.62} color="currentColor"/><span style={{fontWeight: 500}}>62%</span></>;
    case 'dual-bars': return (
      <div style={{display: 'flex', flexDirection: 'column', gap: 2.5, width: 40}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 4}}>
          <span style={{fontSize: 8.5, opacity: 0.7, width: 10, lineHeight: 1}}>C</span>
          <div style={{flex: 1, height: 4, borderRadius: 2, background: isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.14)'}}>
            <div style={{width: '42%', height: '100%', borderRadius: 2, background: isDark ? '#98989D' : '#6C6C70'}}/>
          </div>
        </div>
        <div style={{display: 'flex', alignItems: 'center', gap: 4}}>
          <span style={{fontSize: 8.5, opacity: 0.7, width: 10, lineHeight: 1}}>L</span>
          <div style={{flex: 1, height: 4, borderRadius: 2, background: isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.14)'}}>
            <div style={{width: '78%', height: '100%', borderRadius: 2, background: '#D97757'}}/>
          </div>
        </div>
      </div>
    );
    case 'text-only': return <span style={{fontWeight: 500, letterSpacing: -0.05}}>C 42% · L 78%</span>;
    case 'state-color': return <span style={{color: '#FF9F0A', display: 'inline-flex', alignItems: 'center', gap: 6, fontWeight: 600}}>
      <AppGlyph size={14}/><span>14%</span></span>;
    case 'weekly-mode': return <>
      <AppGlyph size={14}/>
      <span style={{fontWeight: 500}}>62%</span>
      <span style={{fontSize: 9, opacity: 0.55, marginLeft: 2, padding: '1px 4px', borderRadius: 3,
        background: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)',
        letterSpacing: 0.4, textTransform: 'uppercase', fontFamily: 'var(--font-mono)'}}>5h</span>
    </>;
    default: return <AppGlyph size={14}/>;
  }
}

function PopoverByVariant({ variant, theme, onOpenStats, onOpenPrefs }) {
  switch (variant) {
    case 'vertical-list': return <PopV_VerticalList theme={theme} onOpenStats={onOpenStats} onOpenPrefs={onOpenPrefs}/>;
    case 'dense-compact': return <PopV_DenseCompact theme={theme}/>;
    case 'spark-chart': return <PopV_SparkChart theme={theme}/>;
    case 'big-stat': return <PopV_BigStat theme={theme}/>;
    default: return <PopV_VerticalList theme={theme}/>;
  }
}

function HUDByVariant({ variant, theme }) {
  switch (variant) {
    case 'two-row-pill': return <InlineHUD theme={theme} variant="two-row-pill"/>;
    case 'stacked-numbers': return <InlineHUD theme={theme} variant="stacked-numbers"/>;
    case 'dual-rings': return <InlineHUD theme={theme} variant="dual-rings"/>;
    case 'ultra-thin': return <InlineHUD theme={theme} variant="ultra-thin"/>;
    case 'single-service': return <InlineHUD theme={theme} variant="single-service"/>;
    case 'horizontal-slim': return <InlineHUD theme={theme} variant="horizontal-slim"/>;
    case 'five-hour-week': return <InlineHUD theme={theme} variant="five-hour-week"/>;
    case 'no-chrome': return <InlineHUD theme={theme} variant="no-chrome"/>;
    default: return <InlineHUD theme={theme} variant="two-row-pill"/>;
  }
}

// Standalone HUD (no wallpaper frame) — pulled out of the HUDFrame wrapper
function InlineHUD({ variant, theme }) {
  const isDark = theme === 'dark';
  const baseStyle = {
    background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
    backdropFilter: 'saturate(180%) blur(40px)',
    WebkitBackdropFilter: 'saturate(180%) blur(40px)',
    boxShadow: 'var(--shadow-hud)',
    color: 'var(--text-primary)',
  };
  if (variant === 'two-row-pill') {
    return (
      <div style={{...baseStyle, padding: '10px 14px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 7, minWidth: 168}}>
        <HUDRow label="Codex" value={0.42} color={isDark ? '#98989D' : '#6C6C70'} theme={theme}/>
        <HUDRow label="Claude" value={0.78} color={isDark ? '#E68A6E' : '#D97757'} theme={theme}/>
      </div>
    );
  }
  if (variant === 'stacked-numbers') {
    return (
      <div style={{...baseStyle, padding: '10px 14px', borderRadius: 14, display: 'flex', flexDirection: 'column', gap: 4, minWidth: 116}}>
        <div style={{display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12}}>
          <span style={{fontSize: 10, color: 'var(--text-secondary)', letterSpacing: 0.4, textTransform: 'uppercase'}}>Codex</span>
          <span className="tnum" style={{fontSize: 18, fontWeight: 600, color: isDark ? '#98989D' : '#6C6C70', letterSpacing: -0.5}}>42%</span>
        </div>
        <div style={{height: 0.5, background: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}}/>
        <div style={{display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12}}>
          <span style={{fontSize: 10, color: 'var(--text-secondary)', letterSpacing: 0.4, textTransform: 'uppercase'}}>Claude</span>
          <span className="tnum" style={{fontSize: 18, fontWeight: 600, color: isDark ? '#E68A6E' : '#D97757', letterSpacing: -0.5}}>78%</span>
        </div>
      </div>
    );
  }
  if (variant === 'dual-rings') {
    return (
      <div style={{...baseStyle, padding: '10px 12px', borderRadius: 14, display: 'flex', gap: 14}}>
        <MiniRingItem label="Codex" value={0.42} color={isDark ? '#98989D' : '#6C6C70'}/>
        <div style={{width: 0.5, background: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}}/>
        <MiniRingItem label="Claude" value={0.78} color={isDark ? '#E68A6E' : '#D97757'}/>
      </div>
    );
  }
  if (variant === 'ultra-thin') {
    return (
      <div style={{...baseStyle, padding: '8px 12px', borderRadius: 10, display: 'flex', flexDirection: 'column', gap: 4, minWidth: 122}}>
        <div style={{display: 'flex', alignItems: 'center', gap: 8, fontSize: 11}}>
          <span style={{width: 6, height: 6, borderRadius: 1.5, background: isDark ? '#98989D' : '#6C6C70', flexShrink: 0}}/>
          <span style={{color: 'var(--text-secondary)', flex: 1}}>Codex</span>
          <span className="tnum" style={{fontWeight: 600}}>42%</span>
        </div>
        <div style={{display: 'flex', alignItems: 'center', gap: 8, fontSize: 11}}>
          <span style={{width: 6, height: 6, borderRadius: 1.5, background: isDark ? '#E68A6E' : '#D97757', flexShrink: 0}}/>
          <span style={{color: 'var(--text-secondary)', flex: 1}}>Claude</span>
          <span className="tnum" style={{fontWeight: 600}}>78%</span>
        </div>
      </div>
    );
  }
  if (variant === 'single-service') {
    return (
      <div style={{...baseStyle, padding: '10px 14px', borderRadius: 14, display: 'flex', alignItems: 'center', gap: 12, minWidth: 150}}>
        <Ring size={34} stroke={4} value={0.78} color={isDark ? '#E68A6E' : '#D97757'} track="currentColor">
          <span className="tnum" style={{fontSize: 10, fontWeight: 600}}>78</span>
        </Ring>
        <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.1}}>
          <span style={{fontSize: 12, fontWeight: 600}}>Claude Code</span>
          <span style={{fontSize: 10, color: 'var(--text-secondary)'}}>resets in 1h 04m</span>
        </div>
      </div>
    );
  }
  if (variant === 'horizontal-slim') {
    return (
      <div style={{...baseStyle, padding: '8px 14px', borderRadius: 18, display: 'flex', alignItems: 'center', gap: 14}}>
        <span style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5}}>
          <span style={{width: 4, height: 16, borderRadius: 2, background: isDark ? '#98989D' : '#6C6C70'}}/>
          <span style={{fontWeight: 600}}>Codex</span>
          <span className="tnum" style={{color: isDark ? '#98989D' : '#6C6C70', fontWeight: 600}}>42%</span>
        </span>
        <span style={{width: 0.5, height: 18, background: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'}}/>
        <span style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5}}>
          <span style={{width: 4, height: 16, borderRadius: 2, background: isDark ? '#E68A6E' : '#D97757'}}/>
          <span style={{fontWeight: 600}}>Claude</span>
          <span className="tnum" style={{color: isDark ? '#E68A6E' : '#D97757', fontWeight: 600}}>78%</span>
        </span>
      </div>
    );
  }
  if (variant === 'five-hour-week') {
    return (
      <div style={{...baseStyle, padding: '11px 14px', borderRadius: 14,
        display: 'grid',
        gridTemplateColumns: 'auto 1fr auto auto',
        rowGap: 6, columnGap: 10,
        alignItems: 'center', minWidth: 200}}>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)', letterSpacing: 0.4, textTransform: 'uppercase', gridColumn: '2', justifySelf: 'end'}}>5h</span>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)', letterSpacing: 0.4, textTransform: 'uppercase', gridColumn: '4', justifySelf: 'end'}}>wk</span>
        <span style={{fontSize: 10.5, fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: 0.2, textTransform: 'uppercase'}}>Codex</span>
        <div><Bar value={0.42} color={isDark ? '#98989D' : '#6C6C70'} height={4} radius={2}/></div>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 600, color: isDark ? '#98989D' : '#6C6C70'}}>42%</span>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 500, color: 'var(--text-secondary)'}}>31%</span>
        <span style={{fontSize: 10.5, fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: 0.2, textTransform: 'uppercase'}}>Claude</span>
        <div><Bar value={0.78} color={isDark ? '#E68A6E' : '#D97757'} height={4} radius={2}/></div>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 600, color: isDark ? '#E68A6E' : '#D97757'}}>78%</span>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 500, color: 'var(--text-secondary)'}}>54%</span>
      </div>
    );
  }
  if (variant === 'no-chrome') {
    return (
      <div style={{
        padding: '4px 8px',
        textShadow: isDark ? '0 1px 4px rgba(0,0,0,0.6), 0 0 1px rgba(0,0,0,0.8)' : '0 1px 4px rgba(255,255,255,0.55)',
        display: 'flex', flexDirection: 'column', gap: 2,
        minWidth: 88,
      }}>
        <div style={{display: 'flex', justifyContent: 'space-between', gap: 10, fontSize: 12, fontWeight: 600}}>
          <span style={{color: isDark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.8)'}}>Codex</span>
          <span className="tnum" style={{color: isDark ? '#fff' : '#000'}}>42%</span>
        </div>
        <div style={{display: 'flex', justifyContent: 'space-between', gap: 10, fontSize: 12, fontWeight: 600}}>
          <span style={{color: isDark ? 'rgba(255,255,255,0.85)' : 'rgba(0,0,0,0.8)'}}>Claude</span>
          <span className="tnum" style={{color: isDark ? '#fff' : '#000'}}>78%</span>
        </div>
      </div>
    );
  }
  return null;
}

function DraggableHUD({ theme, variant, initialPos, containerRef }) {
  const [pos, setPos] = React.useState(() => {
    if (initialPos === 'topRight') return { x: window.innerWidth - 220, y: 56 };
    if (initialPos === 'topLeft') return { x: 24, y: 56 };
    if (initialPos === 'bottomLeft') return { x: 24, y: window.innerHeight - 130 };
    return { x: window.innerWidth - 220, y: window.innerHeight - 130 };
  });
  const dragRef = React.useRef(null);
  const onPointerDown = (e) => {
    if (e.target.closest('button')) return;
    const start = { x: e.clientX, y: e.clientY, ox: pos.x, oy: pos.y };
    e.currentTarget.setPointerCapture(e.pointerId);
    const onMove = (ev) => {
      setPos({
        x: Math.max(8, Math.min(window.innerWidth - 240, start.ox + (ev.clientX - start.x))),
        y: Math.max(38, Math.min(window.innerHeight - 60, start.oy + (ev.clientY - start.y))),
      });
    };
    const onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  };
  return (
    <div
      ref={dragRef}
      onPointerDown={onPointerDown}
      style={{
        position: 'absolute',
        left: pos.x, top: pos.y,
        cursor: 'grab', userSelect: 'none',
        zIndex: 400,
      }}>
      <HUDByVariant variant={variant} theme={theme}/>
    </div>
  );
}

// Draggable + closable window
function ProtoWindow({ children, onClose, initial }) {
  const [pos, setPos] = React.useState({ x: initial?.x ?? 120, y: initial?.y ?? 80 });
  const [size] = React.useState({ w: initial?.w ?? 900, h: initial?.h ?? 600 });
  const onPointerDown = (e) => {
    if (e.target.closest('button')) return;
    const start = { x: e.clientX, y: e.clientY, ox: pos.x, oy: pos.y };
    e.currentTarget.setPointerCapture(e.pointerId);
    const onMove = (ev) => {
      setPos({
        x: Math.max(-100, Math.min(window.innerWidth - 200, start.ox + (ev.clientX - start.x))),
        y: Math.max(38, Math.min(window.innerHeight - 100, start.oy + (ev.clientY - start.y))),
      });
    };
    const onUp = () => {
      window.removeEventListener('pointermove', onMove);
      window.removeEventListener('pointerup', onUp);
    };
    window.addEventListener('pointermove', onMove);
    window.addEventListener('pointerup', onUp);
  };
  return (
    <div style={{
      position: 'absolute',
      left: pos.x, top: pos.y,
      width: size.w, height: size.h,
      maxWidth: 'calc(100vw - 16px)', maxHeight: 'calc(100vh - 60px)',
      zIndex: 300,
      animation: 'winIn 0.22s cubic-bezier(0.2, 0.9, 0.3, 1.1)',
      filter: 'drop-shadow(0 24px 60px rgba(0,0,0,0.45))',
    }}>
      <div onPointerDown={onPointerDown} style={{position: 'absolute', top: 0, left: 0, right: 60, height: 52, cursor: 'grab', zIndex: 10}}/>
      <button onClick={onClose} style={{
        position: 'absolute', top: 19, left: 16,
        width: 12, height: 12, borderRadius: 6, border: 0,
        background: '#FE5F58',
        cursor: 'pointer', zIndex: 20,
        boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)',
        padding: 0,
      }}/>
      {children}
    </div>
  );
}

function DockHint() {
  return (
    <div style={{
      position: 'absolute',
      bottom: 8, left: '50%', transform: 'translateX(-50%)',
      display: 'flex', alignItems: 'flex-end', gap: 6,
      padding: '6px 8px',
      borderRadius: 18,
      background: 'rgba(255,255,255,0.18)',
      backdropFilter: 'blur(20px)',
      WebkitBackdropFilter: 'blur(20px)',
      boxShadow: 'inset 0 0 0 0.5px rgba(255,255,255,0.4), 0 4px 20px rgba(0,0,0,0.18)',
    }}>
      {['#FF9F0A','#34C759','#5E5CE6','#FF375F','#0A84FF','#BF5AF2','#FF9F0A'].map((c, i) => (
        <span key={i} style={{
          width: 36, height: 36, borderRadius: 9,
          background: `linear-gradient(155deg, ${c}, color-mix(in oklab, ${c} 60%, #000))`,
          boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.2), 0 1px 3px rgba(0,0,0,0.2)',
        }}/>
      ))}
      <span style={{width: 1, height: 32, background: 'rgba(255,255,255,0.25)', margin: '0 4px'}}/>
      <span style={{
        width: 36, height: 36, borderRadius: 9,
        background: 'linear-gradient(155deg, #4A4A4F, #6C6C70 50%, #D97757)',
        boxShadow: 'inset 0 1px 0 rgba(255,255,255,0.2), 0 1px 3px rgba(0,0,0,0.2)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}><AppGlyph size={20} color="#fff"/></span>
    </div>
  );
}

function FirstHint({ theme }) {
  return (
    <div style={{
      position: 'absolute',
      top: 38, right: 100,
      pointerEvents: 'none',
      display: 'flex', alignItems: 'flex-start', gap: 8,
      animation: 'hintFade 0.4s ease',
    }}>
      <svg width="40" height="40" viewBox="0 0 40 40" fill="none" style={{marginTop: -4}}>
        <path d="M28 4C28 4 26 10 22 14C18 18 12 18 6 22" stroke={theme === 'dark' ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)'} strokeWidth="1.5" strokeLinecap="round" strokeDasharray="3 3"/>
        <path d="M30 4L28 4L28 6M28 4L26.5 5.5" stroke={theme === 'dark' ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)'} strokeWidth="1.5" strokeLinecap="round"/>
      </svg>
      <div style={{
        padding: '6px 10px', borderRadius: 8,
        background: theme === 'dark' ? 'rgba(30,30,32,0.75)' : 'rgba(255,255,255,0.75)',
        backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
        color: theme === 'dark' ? '#fff' : '#000',
        fontSize: 11, fontWeight: 500,
        boxShadow: '0 4px 12px rgba(0,0,0,0.18)',
      }}>
        Click cc-bar icon to open<br/><span style={{opacity: 0.65, fontSize: 10}}>点击菜单栏图标</span>
      </div>
    </div>
  );
}

Object.assign(window, { PrototypeApp });
