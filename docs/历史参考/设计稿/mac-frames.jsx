/* Shared macOS chrome — menu bar strip, window chrome, popover container, HUD wrapper.
   Two themes: light + dark wallpaper. Liquid Glass treatment. */

const MAC_WALLPAPERS = {
  light: 'linear-gradient(155deg, #C1D6E8 0%, #DCE3DD 35%, #E5D4C2 70%, #D4B69A 100%)',
  dark:  'linear-gradient(155deg, #1F2A3A 0%, #2A2235 40%, #3A2330 75%, #4A2A38 100%)',
};

// Menu bar strip with system icons (used to show menu bar icon variants in context).
// `app` is the rendered app icon/text; passing children paints a wider menu bar context.
function MenuBarStrip({ theme = 'dark', children, wallpaperOffset = 0, height = 30, label }) {
  const isDark = theme === 'dark';
  const wp = isDark ? MAC_WALLPAPERS.dark : MAC_WALLPAPERS.light;
  return (
    <div className={'theme-' + theme} style={{
      width: '100%', height: '100%',
      background: wp, backgroundPositionY: wallpaperOffset,
      fontFamily: 'var(--font-sf)', color: 'var(--text-primary)',
      display: 'flex', flexDirection: 'column',
      position: 'relative', overflow: 'hidden',
    }}>
      {/* the menu bar itself — translucent strip across top */}
      <div style={{
        height, flex: '0 0 ' + height + 'px',
        backdropFilter: 'saturate(140%) blur(20px)',
        WebkitBackdropFilter: 'saturate(140%) blur(20px)',
        background: isDark ? 'rgba(20,20,22,0.42)' : 'rgba(255,255,255,0.32)',
        borderBottom: isDark ? '0.5px solid rgba(255,255,255,0.06)' : '0.5px solid rgba(0,0,0,0.06)',
        display: 'flex', alignItems: 'center',
        paddingLeft: 14, paddingRight: 14,
        fontSize: 13, letterSpacing: -0.08,
        color: isDark ? '#F5F5F7' : '#1D1D1F',
      }}>
        {/* Apple logo */}
        <svg width="13" height="15" viewBox="0 0 14 16" fill="currentColor" style={{marginRight: 16, opacity: 0.95}}>
          <path d="M11.182 8.34c-.02-2.069 1.687-3.063 1.763-3.111-.96-1.405-2.456-1.597-2.99-1.62-1.272-.129-2.485.749-3.132.749-.648 0-1.647-.73-2.706-.71-1.394.022-2.679.809-3.395 2.054-1.448 2.508-.371 6.221 1.039 8.26.685.998 1.503 2.119 2.578 2.079 1.034-.041 1.426-.668 2.676-.668 1.249 0 1.602.668 2.7.65 1.114-.02 1.821-1.018 2.502-2.019.787-1.158 1.114-2.282 1.135-2.34-.025-.011-2.168-.832-2.189-3.323zM9.085 2.298C9.66 1.604 10.046.628 9.94-.343c-.835.034-1.844.555-2.435 1.247-.532.616-.997 1.602-.872 2.555.929.072 1.878-.471 2.452-1.161z"/>
        </svg>
        {/* App menus */}
        <span style={{fontWeight: 600, marginRight: 20}}>Finder</span>
        <span style={{marginRight: 16}}>File</span>
        <span style={{marginRight: 16}}>Edit</span>
        <span style={{marginRight: 16}}>View</span>
        <span style={{marginRight: 16, opacity: 0.85}}>Go</span>
        <span style={{opacity: 0.85}}>Window</span>

        {/* Right side: status items */}
        <div style={{marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 14}}>
          {children}
          {/* battery */}
          <svg width="26" height="12" viewBox="0 0 26 12" fill="none" style={{opacity: 0.9}}>
            <rect x="0.5" y="0.5" width="22" height="11" rx="3" stroke="currentColor" strokeOpacity="0.5"/>
            <rect x="2" y="2" width="14" height="8" rx="1.5" fill="currentColor" fillOpacity="0.95"/>
            <rect x="23.5" y="3.5" width="2" height="5" rx="1" fill="currentColor" fillOpacity="0.5"/>
          </svg>
          {/* wifi */}
          <svg width="15" height="11" viewBox="0 0 15 11" fill="currentColor" style={{opacity: 0.95}}>
            <path d="M7.5 0C4.7 0 2.1 1 .1 2.7l1.2 1.4C3 2.7 5.2 1.8 7.5 1.8s4.5.9 6.2 2.3l1.2-1.4C12.9 1 10.3 0 7.5 0zm0 3.6c-1.9 0-3.7.7-5.1 1.9l1.2 1.4c1.1-.9 2.4-1.5 3.9-1.5s2.9.5 3.9 1.5l1.2-1.4c-1.4-1.2-3.2-1.9-5.1-1.9zm0 3.6c-1 0-1.9.4-2.6 1l1.2 1.4c.4-.4 1-.6 1.4-.6s1 .2 1.4.6l1.2-1.4c-.7-.6-1.6-1-2.6-1z"/>
          </svg>
          {/* control center */}
          <svg width="15" height="12" viewBox="0 0 16 12" fill="none" style={{opacity: 0.9}}>
            <rect x="0" y="0" width="16" height="3" rx="1" fill="currentColor" fillOpacity="0.65"/>
            <rect x="0" y="4.5" width="11" height="3" rx="1" fill="currentColor" fillOpacity="0.85"/>
            <rect x="0" y="9" width="16" height="3" rx="1" fill="currentColor" fillOpacity="0.65"/>
          </svg>
          {/* clock */}
          <span style={{fontSize: 13, fontVariantNumeric: 'tabular-nums'}}>Tue 14 Aug 10:42 AM</span>
        </div>
      </div>
      {/* Below menu bar: shows nothing or label */}
      {label && (
        <div style={{
          position: 'absolute', left: 12, bottom: 8,
          fontSize: 10, color: isDark ? 'rgba(255,255,255,0.5)' : 'rgba(0,0,0,0.45)',
          fontFamily: 'var(--font-mono)',
          letterSpacing: 0.2,
        }}>{label}</div>
      )}
    </div>
  );
}

// macOS Window with traffic lights, title bar
function MacWindow({ theme = 'dark', title, subtitle, toolbar, children, contentStyle, width, height }) {
  const isDark = theme === 'dark';
  return (
    <div className={'theme-' + theme} style={{
      width: width || '100%', height: height || '100%',
      borderRadius: 'var(--r-window)',
      background: 'var(--window-bg)',
      boxShadow: 'var(--shadow-window)',
      overflow: 'hidden',
      display: 'flex', flexDirection: 'column',
      fontFamily: 'var(--font-sf)',
      color: 'var(--text-primary)',
      position: 'relative',
    }}>
      {/* title bar */}
      <div style={{
        flex: '0 0 auto',
        height: 52,
        display: 'flex', alignItems: 'center',
        padding: '0 16px',
        background: isDark ? 'rgba(46,46,48,0.72)' : 'rgba(246,246,247,0.72)',
        backdropFilter: 'saturate(180%) blur(20px)',
        WebkitBackdropFilter: 'saturate(180%) blur(20px)',
        borderBottom: '0.5px solid var(--separator)',
        gap: 12,
      }}>
        {/* traffic lights */}
        <div style={{display: 'flex', gap: 8, marginRight: 4}}>
          <span style={{width: 12, height: 12, borderRadius: 6, background: '#FE5F58', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)'}}></span>
          <span style={{width: 12, height: 12, borderRadius: 6, background: '#FEBC2E', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)'}}></span>
          <span style={{width: 12, height: 12, borderRadius: 6, background: '#28C840', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.18)'}}></span>
        </div>
        {/* title or toolbar */}
        {toolbar
          ? <div style={{flex: 1, display: 'flex', alignItems: 'center', gap: 8}}>{toolbar}</div>
          : (
            <div style={{flex: 1, textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', lineHeight: 1.1}}>
              {title && <div style={{fontSize: 13, fontWeight: 600, letterSpacing: -0.1}}>{title}</div>}
              {subtitle && <div style={{fontSize: 11, color: 'var(--text-secondary)', marginTop: 2}}>{subtitle}</div>}
            </div>
          )
        }
        <div style={{width: 60, flex: '0 0 60px'}}></div>
      </div>
      {/* content */}
      <div style={{flex: 1, minHeight: 0, overflow: 'hidden', ...contentStyle}}>{children}</div>
    </div>
  );
}

// Popover with the small arrow notch at top, pointing up at menu bar
function MacPopover({ theme = 'dark', width = 360, height, children, arrowOffset = 'auto' }) {
  const isDark = theme === 'dark';
  return (
    <div className={'theme-' + theme} style={{
      width, height, position: 'relative',
      fontFamily: 'var(--font-sf)',
      color: 'var(--text-primary)',
    }}>
      {/* arrow notch */}
      <div style={{
        position: 'absolute',
        top: 0,
        right: arrowOffset === 'auto' ? 28 : arrowOffset,
        width: 14, height: 7, overflow: 'hidden',
        marginTop: -7,
      }}>
        <div style={{
          width: 14, height: 14, marginTop: 0,
          background: isDark ? 'rgba(40,40,42,0.92)' : 'rgba(252,252,253,0.85)',
          backdropFilter: 'saturate(180%) blur(30px)',
          WebkitBackdropFilter: 'saturate(180%) blur(30px)',
          transform: 'rotate(45deg) translate(0, 5px)',
          boxShadow: isDark
            ? '0 0 0 0.5px rgba(255,255,255,0.08)'
            : '0 0 0 0.5px rgba(0,0,0,0.1)',
        }}></div>
      </div>
      <div className="lg-surface" style={{
        width: '100%',
        height: height || 'auto',
        background: isDark ? 'rgba(40,40,42,0.84)' : 'rgba(252,252,253,0.78)',
        backdropFilter: 'saturate(180%) blur(40px)',
        WebkitBackdropFilter: 'saturate(180%) blur(40px)',
        borderRadius: 'var(--r-popover)',
        boxShadow: 'var(--shadow-popover)',
        overflow: 'hidden',
        position: 'relative',
        zIndex: 1,
      }}>
        {children}
      </div>
    </div>
  );
}

// HUD floating wrapper — sits over a wallpaper. children is the HUD content.
function HUDFrame({ theme = 'dark', children, width = 280, height = 110, wallpaperOnly = false }) {
  const isDark = theme === 'dark';
  const wp = isDark ? MAC_WALLPAPERS.dark : MAC_WALLPAPERS.light;
  return (
    <div className={'theme-' + theme} style={{
      width: '100%', height: '100%',
      background: wp,
      position: 'relative',
      overflow: 'hidden',
      fontFamily: 'var(--font-sf)',
      color: 'var(--text-primary)',
    }}>
      {!wallpaperOnly && (
        <div style={{
          position: 'absolute',
          top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
          width, height,
        }}>
          {children}
        </div>
      )}
      {wallpaperOnly && children}
    </div>
  );
}

// Mini logo glyphs
function CodexGlyph({ size = 14, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <path d="M8 1.5L13.5 4.5V11.5L8 14.5L2.5 11.5V4.5L8 1.5Z" stroke={color || 'currentColor'} strokeWidth="1.4" strokeLinejoin="round"/>
      <path d="M5.5 7L7 8.5L10.5 5" stroke={color || 'currentColor'} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}
function CCGlyph({ size = 14, color }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <path d="M3 4.5C3 3.4 3.9 2.5 5 2.5H11C12.1 2.5 13 3.4 13 4.5V10.5C13 11.6 12.1 12.5 11 12.5H7L3.5 14.5V4.5Z" stroke={color || 'currentColor'} strokeWidth="1.4" strokeLinejoin="round"/>
      <path d="M6.5 6.5L8 8L6.5 9.5" stroke={color || 'currentColor'} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M8.5 9.5H10.5" stroke={color || 'currentColor'} strokeWidth="1.4" strokeLinecap="round"/>
    </svg>
  );
}
function AppGlyph({ size = 14, color }) {
  // Combined app icon — sparkle/gauge hybrid
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none">
      <circle cx="8" cy="8.5" r="5.5" stroke={color || 'currentColor'} strokeWidth="1.4"/>
      <path d="M5.5 9.5L7.5 7.5L9 9L11 6.5" stroke={color || 'currentColor'} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
      <circle cx="8" cy="2.5" r="0.8" fill={color || 'currentColor'}/>
    </svg>
  );
}

// Tiny progress ring used in many places
function Ring({ size = 18, stroke = 2.5, value = 0.42, color, track, label, labelStyle, children }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <div style={{position: 'relative', width: size, height: size, display: 'inline-block'}}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{transform: 'rotate(-90deg)'}}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={track || 'currentColor'} strokeOpacity={0.18} strokeWidth={stroke}/>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color || 'currentColor'} strokeWidth={stroke} strokeLinecap="round"
          strokeDasharray={c} strokeDashoffset={c * (1 - value)}/>
      </svg>
      {(label || children) && (
        <div style={{
          position: 'absolute', inset: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: size * 0.32, fontWeight: 600,
          fontVariantNumeric: 'tabular-nums',
          ...labelStyle,
        }}>{children || label}</div>
      )}
    </div>
  );
}

// Mini horizontal progress bar with rounded fill
function Bar({ value = 0.42, color, bg, height = 6, width = '100%', radius }) {
  return (
    <div style={{
      width, height, background: bg || 'var(--fill)',
      borderRadius: radius ?? height/2, overflow: 'hidden',
    }}>
      <div style={{
        width: (Math.min(1, Math.max(0, value)) * 100) + '%', height: '100%',
        background: color || 'var(--accent)',
        borderRadius: radius ?? height/2,
        transition: 'width 0.3s',
      }}/>
    </div>
  );
}

Object.assign(window, {
  MenuBarStrip, MacWindow, MacPopover, HUDFrame,
  CodexGlyph, CCGlyph, AppGlyph, Ring, Bar,
  MAC_WALLPAPERS,
});
