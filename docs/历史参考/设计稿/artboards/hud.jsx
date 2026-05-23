// HUD variants — floating windows that sit on the desktop.
// Per spec: minimal (two rows percentages + labels). We do 6 takes on "minimal".

// Variant 1 — Two-row pill: side label + percent + tiny bar
function HUDV_TwoRowPill({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '10px 14px',
        borderRadius: 14,
        background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'flex', flexDirection: 'column', gap: 7,
        minWidth: 168,
      }}>
        <HUDRow label="Codex" value={0.42} color="#98989D" theme={theme}/>
        <HUDRow label="Claude" value={0.78} color="#E68A6E" theme={theme}/>
      </div>
    </HUDFrame>
  );
}

function HUDRow({ label, value, color, theme }) {
  return (
    <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
      <span style={{
        fontSize: 10.5, fontWeight: 600, letterSpacing: 0.3,
        textTransform: 'uppercase',
        color: 'var(--text-secondary)',
        width: 44, flexShrink: 0,
      }}>{label}</span>
      <div style={{flex: 1, minWidth: 56}}><Bar value={value} color={color} height={4} radius={2}/></div>
      <span className="tnum" style={{
        fontSize: 13, fontWeight: 600, color, minWidth: 34, textAlign: 'right',
        letterSpacing: -0.3,
      }}>{Math.round(value*100)}%</span>
    </div>
  );
}

// Variant 2 — Stacked numbers (no bars, just big numbers)
function HUDV_StackedNumbers({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '10px 14px',
        borderRadius: 14,
        background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'flex', flexDirection: 'column', gap: 4,
        minWidth: 116,
      }}>
        <div style={{display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12}}>
          <span style={{fontSize: 10, color: 'var(--text-secondary)', letterSpacing: 0.4, textTransform: 'uppercase'}}>Codex</span>
          <span className="tnum" style={{fontSize: 18, fontWeight: 600, color: '#98989D', letterSpacing: -0.5}}>42%</span>
        </div>
        <div style={{height: 0.5, background: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}}/>
        <div style={{display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', gap: 12}}>
          <span style={{fontSize: 10, color: 'var(--text-secondary)', letterSpacing: 0.4, textTransform: 'uppercase'}}>Claude</span>
          <span className="tnum" style={{fontSize: 18, fontWeight: 600, color: '#E68A6E', letterSpacing: -0.5}}>78%</span>
        </div>
      </div>
    </HUDFrame>
  );
}

// Variant 3 — Dual mini rings
function HUDV_DualRings({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '10px 12px',
        borderRadius: 14,
        background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'flex', gap: 14,
      }}>
        <MiniRingItem label="Codex" value={0.42} color="#98989D"/>
        <div style={{width: 0.5, background: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}}/>
        <MiniRingItem label="Claude" value={0.78} color="#E68A6E"/>
      </div>
    </HUDFrame>
  );
}

function MiniRingItem({ label, value, color }) {
  return (
    <div style={{display: 'flex', alignItems: 'center', gap: 8}}>
      <Ring size={26} stroke={3.5} value={value} color={color} track="currentColor"/>
      <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.05}}>
        <span className="tnum" style={{fontSize: 14, fontWeight: 600, color, letterSpacing: -0.3}}>{Math.round(value*100)}%</span>
        <span style={{fontSize: 9, color: 'var(--text-secondary)', letterSpacing: 0.3, textTransform: 'uppercase'}}>{label}</span>
      </div>
    </div>
  );
}

// Variant 4 — Ultra-minimal: just colored bars with labels, no chrome
function HUDV_UltraThin({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '8px 12px',
        borderRadius: 10,
        background: isDark ? 'rgba(28,28,30,0.48)' : 'rgba(255,255,255,0.48)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'flex', flexDirection: 'column', gap: 4,
        minWidth: 122,
      }}>
        <div style={{display: 'flex', alignItems: 'center', gap: 8, fontSize: 11}}>
          <span style={{width: 6, height: 6, borderRadius: 1.5, background: '#98989D', flexShrink: 0}}/>
          <span style={{color: 'var(--text-secondary)', flex: 1}}>Codex</span>
          <span className="tnum" style={{fontWeight: 600}}>42%</span>
        </div>
        <div style={{display: 'flex', alignItems: 'center', gap: 8, fontSize: 11}}>
          <span style={{width: 6, height: 6, borderRadius: 1.5, background: '#E68A6E', flexShrink: 0}}/>
          <span style={{color: 'var(--text-secondary)', flex: 1}}>Claude</span>
          <span className="tnum" style={{fontWeight: 600}}>78%</span>
        </div>
      </div>
    </HUDFrame>
  );
}

// Variant 5 — Single service mode (CC only)
function HUDV_SingleService({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '10px 14px',
        borderRadius: 14,
        background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'flex', alignItems: 'center', gap: 12,
        minWidth: 150,
      }}>
        <Ring size={34} stroke={4} value={0.78} color="#E68A6E" track="currentColor">
          <span className="tnum" style={{fontSize: 10, fontWeight: 600}}>78</span>
        </Ring>
        <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.1}}>
          <span style={{fontSize: 12, fontWeight: 600}}>Claude Code</span>
          <span style={{fontSize: 10, color: 'var(--text-secondary)'}}>resets in 1h 04m</span>
        </div>
      </div>
    </HUDFrame>
  );
}

// Variant 6 — Long horizontal bar: side-by-side w/ slim profile
function HUDV_HorizontalSlim({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '8px 14px',
        borderRadius: 18,
        background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <span style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5}}>
          <span style={{width: 4, height: 16, borderRadius: 2, background: '#98989D'}}/>
          <span style={{fontWeight: 600}}>Codex</span>
          <span className="tnum" style={{color: '#98989D', fontWeight: 600}}>42%</span>
        </span>
        <span style={{width: 0.5, height: 18, background: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'}}/>
        <span style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5}}>
          <span style={{width: 4, height: 16, borderRadius: 2, background: '#E68A6E'}}/>
          <span style={{fontWeight: 600}}>Claude</span>
          <span className="tnum" style={{color: '#E68A6E', fontWeight: 600}}>78%</span>
        </span>
      </div>
    </HUDFrame>
  );
}

// Variant 7 — Verbose mode (5h + week)
function HUDV_FiveHourWeek({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div className="lg-surface" style={{
        padding: '11px 14px',
        borderRadius: 14,
        background: isDark ? 'rgba(28,28,30,0.62)' : 'rgba(255,255,255,0.58)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        boxShadow: 'var(--shadow-hud)',
        display: 'grid',
        gridTemplateColumns: 'auto 1fr auto auto',
        rowGap: 6, columnGap: 10,
        alignItems: 'center',
        minWidth: 200,
      }}>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)', letterSpacing: 0.4, textTransform: 'uppercase', gridColumn: '2', justifySelf: 'end'}}>5h</span>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)', letterSpacing: 0.4, textTransform: 'uppercase', gridColumn: '4', justifySelf: 'end'}}>wk</span>

        <span style={{fontSize: 10.5, fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: 0.2, textTransform: 'uppercase'}}>Codex</span>
        <div><Bar value={0.42} color="#98989D" height={4} radius={2}/></div>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 600, color: '#98989D'}}>42%</span>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 500, color: 'var(--text-secondary)'}}>31%</span>

        <span style={{fontSize: 10.5, fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: 0.2, textTransform: 'uppercase'}}>Claude</span>
        <div><Bar value={0.78} color="#E68A6E" height={4} radius={2}/></div>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 600, color: '#E68A6E'}}>78%</span>
        <span className="tnum" style={{fontSize: 11.5, fontWeight: 500, color: 'var(--text-secondary)'}}>54%</span>
      </div>
    </HUDFrame>
  );
}

// Variant 8 — Even more minimal: pure floating text, no chrome
function HUDV_NoChrome({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <HUDFrame theme={theme}>
      <div style={{
        padding: '4px 8px',
        textShadow: isDark
          ? '0 1px 4px rgba(0,0,0,0.5), 0 0 1px rgba(0,0,0,0.7)'
          : '0 1px 4px rgba(255,255,255,0.5)',
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
    </HUDFrame>
  );
}

Object.assign(window, {
  HUDV_TwoRowPill, HUDV_StackedNumbers, HUDV_DualRings, HUDV_UltraThin,
  HUDV_SingleService, HUDV_HorizontalSlim, HUDV_FiveHourWeek, HUDV_NoChrome,
  HUDRow, MiniRingItem,
});
