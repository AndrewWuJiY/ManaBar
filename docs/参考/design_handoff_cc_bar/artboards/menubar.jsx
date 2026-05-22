// Menu bar icon variants. Each artboard shows a strip of menu bar with
// the variant icon installed, plus a closeup beneath.

function MenuBarItem({ children, active, theme }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 6,
      height: 22, padding: '0 7px',
      borderRadius: 5,
      background: active
        ? (isDark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.08)')
        : 'transparent',
      fontSize: 12.5, letterSpacing: -0.05,
      fontVariantNumeric: 'tabular-nums',
      color: isDark ? '#F5F5F7' : '#1D1D1F',
    }}>{children}</div>
  );
}

function MenuBarCloseup({ theme, label, children, en, cn }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      position: 'absolute', left: 16, bottom: 14,
      display: 'flex', alignItems: 'center', gap: 14,
    }}>
      <div style={{
        padding: '6px 10px', borderRadius: 10,
        background: isDark ? 'rgba(20,20,22,0.6)' : 'rgba(255,255,255,0.6)',
        backdropFilter: 'saturate(140%) blur(20px)',
        WebkitBackdropFilter: 'saturate(140%) blur(20px)',
        boxShadow: isDark ? '0 0 0 0.5px rgba(255,255,255,0.1)' : '0 0 0 0.5px rgba(0,0,0,0.1)',
        transform: 'scale(2.4)',
        transformOrigin: 'left center',
        display: 'inline-flex', alignItems: 'center', gap: 6,
      }}>
        {children}
      </div>
      <div style={{
        marginLeft: 140,
        display: 'flex', flexDirection: 'column',
        fontFamily: 'var(--font-mono)',
        fontSize: 10,
        color: isDark ? 'rgba(255,255,255,0.6)' : 'rgba(0,0,0,0.5)',
      }}>
        {en && <div>{en}</div>}
        {cn && <div style={{opacity: 0.7}}>{cn}</div>}
      </div>
    </div>
  );
}

// Variant 1 — Single combined icon, no number
function MBV_IconOnly({ theme = 'dark' }) {
  return (
    <MenuBarStrip theme={theme} label="V1 · Icon only · 仅图标">
      <MenuBarItem theme={theme}>
        <AppGlyph size={14}/>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Idle • compact" cn="待机 · 紧凑">
        <AppGlyph size={14}/>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 2 — Icon + percent (combined / overall)
function MBV_IconPercent({ theme = 'dark' }) {
  return (
    <MenuBarStrip theme={theme} label="V2 · Icon + %  ·  图标加百分比 (推荐 / default)">
      <MenuBarItem theme={theme}>
        <AppGlyph size={14}/>
        <span style={{fontWeight: 500}}>62%</span>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Single % — averaged" cn="单一百分比 · 平均值">
        <AppGlyph size={14}/>
        <span style={{fontWeight: 500, fontSize: 12.5}}>62%</span>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 3 — Two pills side-by-side (Codex • CC)
function MBV_TwoPills({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <MenuBarStrip theme={theme} label="V3 · Two pills  ·  双服务并排">
      <MenuBarItem theme={theme}>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 4,
          padding: '2px 6px', borderRadius: 4,
          background: isDark ? 'rgba(152,152,157,0.22)' : 'rgba(108,108,112,0.18)',
          fontSize: 11.5, fontWeight: 600, letterSpacing: -0.1,
        }}>
          <span style={{opacity: 0.7}}>C</span>
          <span>42%</span>
        </span>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 4,
          padding: '2px 6px', borderRadius: 4,
          background: isDark ? 'rgba(230,138,110,0.26)' : 'rgba(217,119,87,0.22)',
          fontSize: 11.5, fontWeight: 600, letterSpacing: -0.1,
        }}>
          <span style={{opacity: 0.7}}>CC</span>
          <span>78%</span>
        </span>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Codex grey · Claude peach" cn="并列展示两个服务">
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 3,
          padding: '2px 5px', borderRadius: 4,
          background: isDark ? 'rgba(152,152,157,0.26)' : 'rgba(108,108,112,0.2)',
          fontSize: 11, fontWeight: 600, letterSpacing: -0.1,
        }}>C 42%</span>
        <span style={{
          display: 'inline-flex', alignItems: 'center', gap: 3,
          padding: '2px 5px', borderRadius: 4,
          background: isDark ? 'rgba(230,138,110,0.3)' : 'rgba(217,119,87,0.24)',
          fontSize: 11, fontWeight: 600, letterSpacing: -0.1,
        }}>CC 78%</span>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 4 — Mini progress ring + percent
function MBV_RingPercent({ theme = 'dark' }) {
  return (
    <MenuBarStrip theme={theme} label="V4 · Ring + %  ·  环形进度">
      <MenuBarItem theme={theme}>
        <Ring size={14} stroke={2.2} value={0.62} color="var(--text-primary)"/>
        <span style={{fontWeight: 500}}>62%</span>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Ring fills with usage" cn="环形跟随用量">
        <Ring size={14} stroke={2.2} value={0.62} color="currentColor"/>
        <span style={{fontWeight: 500, fontSize: 12.5}}>62%</span>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 5 — Dual stacked mini bars (two narrow bars stacked vertically)
function MBV_DualBars({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <MenuBarStrip theme={theme} label="V5 · Dual bars  ·  双行迷你条">
      <MenuBarItem theme={theme}>
        <div style={{display: 'flex', flexDirection: 'column', gap: 2, width: 28, padding: '2px 0'}}>
          <div style={{display: 'flex', alignItems: 'center', gap: 3}}>
            <span style={{fontSize: 8, opacity: 0.6, width: 8, lineHeight: 1}}>C</span>
            <div style={{flex: 1, height: 3, borderRadius: 1.5, background: isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.12)'}}>
              <div style={{width: '42%', height: '100%', borderRadius: 1.5, background: isDark ? '#98989D' : '#6C6C70'}}/>
            </div>
          </div>
          <div style={{display: 'flex', alignItems: 'center', gap: 3}}>
            <span style={{fontSize: 8, opacity: 0.6, width: 8, lineHeight: 1}}>L</span>
            <div style={{flex: 1, height: 3, borderRadius: 1.5, background: isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.12)'}}>
              <div style={{width: '78%', height: '100%', borderRadius: 1.5, background: '#D97757'}}/>
            </div>
          </div>
        </div>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Glanceable two-row bars" cn="一目了然 · 上 Codex 下 Claude">
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
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 6 — Text only "C 42% · L 78%"
function MBV_TextOnly({ theme = 'dark' }) {
  return (
    <MenuBarStrip theme={theme} label="V6 · Text only  ·  纯文字">
      <MenuBarItem theme={theme}>
        <span style={{fontWeight: 500, letterSpacing: -0.05}}>C 42% · L 78%</span>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Compact text, no icon" cn="文字最紧凑">
        <span style={{fontWeight: 500, fontSize: 12.5, letterSpacing: -0.05}}>C 42% · L 78%</span>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 7 — Icon + percent with a tinted color (turns orange when low)
function MBV_StateColor({ theme = 'dark' }) {
  return (
    <MenuBarStrip theme={theme} label="V7 · State color  ·  按状态变色 (低于 20% 转橙)">
      <MenuBarItem theme={theme}>
        <span style={{color: '#FF9F0A', display: 'inline-flex', alignItems: 'center', gap: 6, fontWeight: 600}}>
          <AppGlyph size={14}/>
          <span>14%</span>
        </span>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Warning state · orange" cn="低额度警告">
        <span style={{color: '#FF9F0A', display: 'inline-flex', alignItems: 'center', gap: 6, fontWeight: 600, fontSize: 12.5}}>
          <AppGlyph size={14}/>
          <span>14%</span>
        </span>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

// Variant 8 — Weekly mode toggle: shows 5h or weekly
function MBV_WeeklyMode({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <MenuBarStrip theme={theme} label="V8 · 5h ↔ Weekly  ·  5小时 / 周额度 切换">
      <MenuBarItem theme={theme}>
        <AppGlyph size={14}/>
        <span style={{fontWeight: 500}}>62%</span>
        <span style={{
          fontSize: 9, opacity: 0.5, marginLeft: 2,
          padding: '1px 4px', borderRadius: 3,
          background: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)',
          letterSpacing: 0.3, textTransform: 'uppercase',
          fontFamily: 'var(--font-mono)',
        }}>5h</span>
      </MenuBarItem>
      <MenuBarCloseup theme={theme} en="Period chip indicates window" cn="后缀指示时段">
        <AppGlyph size={14}/>
        <span style={{fontWeight: 500, fontSize: 12.5}}>62%</span>
        <span style={{
          fontSize: 9, opacity: 0.55, marginLeft: 2,
          padding: '1px 4px', borderRadius: 3,
          background: isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)',
          letterSpacing: 0.4, textTransform: 'uppercase',
          fontFamily: 'var(--font-mono)',
        }}>5h</span>
      </MenuBarCloseup>
    </MenuBarStrip>
  );
}

Object.assign(window, {
  MBV_IconOnly, MBV_IconPercent, MBV_TwoPills, MBV_RingPercent,
  MBV_DualBars, MBV_TextOnly, MBV_StateColor, MBV_WeeklyMode,
  MenuBarItem,
});
