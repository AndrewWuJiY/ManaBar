// Popover variants — the panel that opens when user clicks the menu bar icon.

// Shared little parts ----------------------------------------------------

function ServiceHeader({ name, cn, sub, color, glyph, theme }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 9,
      padding: '0 2px',
    }}>
      <span style={{
        width: 22, height: 22, borderRadius: 6,
        background: color, color: '#fff',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>{glyph}</span>
      <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.08}}>
        <span style={{fontSize: 13, fontWeight: 600, letterSpacing: -0.1}}>{name}</span>
        {cn && <span style={{fontSize: 10.5, color: 'var(--text-secondary)'}}>{cn}</span>}
      </div>
      {sub && <span style={{
        marginLeft: 'auto',
        fontSize: 11, color: 'var(--text-secondary)',
        fontVariantNumeric: 'tabular-nums',
      }}>{sub}</span>}
    </div>
  );
}

function StatRow({ label, cn, value, sub, valueColor }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      padding: '4px 0',
    }}>
      <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.15}}>
        <span style={{fontSize: 11.5, color: 'var(--text-secondary)'}}>{label}</span>
        {cn && <span style={{fontSize: 10, color: 'var(--text-tertiary)', marginTop: 1}}>{cn}</span>}
      </div>
      <div style={{textAlign: 'right', lineHeight: 1.15}}>
        <span className="tnum" style={{fontSize: 12.5, fontWeight: 500, color: valueColor || 'var(--text-primary)'}}>{value}</span>
        {sub && <div className="tnum" style={{fontSize: 10, color: 'var(--text-tertiary)'}}>{sub}</div>}
      </div>
    </div>
  );
}

// Variant A — Vertical list. Codex up top, CC below. Big ring + table of stats.
function PopV_VerticalList({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <MacPopover theme={theme} width={340}>
      {/* header */}
      <div style={{
        display: 'flex', alignItems: 'center',
        padding: '14px 16px 12px',
        borderBottom: '0.5px solid var(--separator)',
      }}>
        <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.1}}>
          <span style={{fontSize: 13, fontWeight: 600}}>Usage</span>
          <span style={{fontSize: 11, color: 'var(--text-secondary)'}}>用量 · refreshed 32s ago</span>
        </div>
        <div style={{marginLeft: 'auto', display: 'flex', gap: 4}}>
          <PopIconBtn theme={theme}><svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M14 8C14 11.3 11.3 14 8 14C5.5 14 3.3 12.5 2.3 10.3M2 8C2 4.7 4.7 2 8 2C10.5 2 12.7 3.5 13.7 5.7" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/><path d="M2 2.5V5.7H5.2M14 13.5V10.3H10.8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/></svg></PopIconBtn>
          <PopIconBtn theme={theme}><svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M3 5L8 9.5L13 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg></PopIconBtn>
        </div>
      </div>

      {/* Codex block */}
      <ServiceBlock
        theme={theme}
        name="Codex" cn="OpenAI · Plus"
        color="#6C6C70"
        glyph={<CodexGlyph size={14} color="#fff"/>}
        value5h={0.42}
        valueWeek={0.31}
        resetIn="2h 18m"
        tokens="184k / 440k"
        spend="$12.40"
      />

      <div style={{height: 0.5, background: 'var(--separator)', margin: '0 16px'}}/>

      {/* Claude Code block */}
      <ServiceBlock
        theme={theme}
        name="Claude Code" cn="Anthropic · Max 20×"
        color="#D97757"
        glyph={<CCGlyph size={14} color="#fff"/>}
        value5h={0.78}
        valueWeek={0.54}
        resetIn="1h 04m"
        tokens="6.2M / 8M"
        spend="$48.10"
      />

      {/* footer actions */}
      <div style={{
        padding: '10px 12px',
        borderTop: '0.5px solid var(--separator)',
        display: 'flex', alignItems: 'center', gap: 4,
        background: isDark ? 'rgba(255,255,255,0.025)' : 'rgba(0,0,0,0.015)',
      }}>
        <PopMenuItem theme={theme} icon={<svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M3 8H13M3 4H13M3 12H10" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/></svg>}>
          <span className="bilingual"><span>Open Statistics</span><span className="cn">查看统计</span></span>
        </PopMenuItem>
        <div style={{marginLeft: 'auto', display: 'flex', gap: 4}}>
          <PopIconBtn theme={theme}><svg width="14" height="14" viewBox="0 0 16 16" fill="none"><circle cx="8" cy="8" r="5" stroke="currentColor" strokeWidth="1.4"/><path d="M8 1V3M8 13V15M1 8H3M13 8H15M3 3L4.5 4.5M11.5 11.5L13 13M3 13L4.5 11.5M11.5 4.5L13 3" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/></svg></PopIconBtn>
          <PopIconBtn theme={theme}><svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M8 1L9 5L13 6L9 7L8 11L7 7L3 6L7 5L8 1Z" stroke="currentColor" strokeWidth="1.3" strokeLinejoin="round"/></svg></PopIconBtn>
        </div>
      </div>
    </MacPopover>
  );
}

function ServiceBlock({ theme, name, cn, color, glyph, value5h, valueWeek, resetIn, tokens, spend }) {
  return (
    <div style={{padding: '14px 16px'}}>
      <ServiceHeader theme={theme} name={name} cn={cn} color={color} glyph={glyph} sub={`resets in ${resetIn}`}/>
      <div style={{display: 'flex', alignItems: 'center', gap: 14, marginTop: 12}}>
        <Ring size={56} stroke={5.5} value={value5h} color={color} track="currentColor">
          <div style={{textAlign: 'center', lineHeight: 1}}>
            <div style={{fontSize: 14, fontWeight: 600}}>{Math.round(value5h * 100)}%</div>
            <div style={{fontSize: 8, color: 'var(--text-tertiary)', marginTop: 1, letterSpacing: 0.2}}>5H</div>
          </div>
        </Ring>
        <div style={{flex: 1}}>
          <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 10.5, color: 'var(--text-secondary)', marginBottom: 4}}>
            <span>Weekly · 周额度</span>
            <span className="tnum">{Math.round(valueWeek * 100)}%</span>
          </div>
          <Bar value={valueWeek} color={color} height={5}/>
          <div style={{display: 'flex', gap: 14, marginTop: 9, fontSize: 11, color: 'var(--text-secondary)'}}>
            <div><span className="tnum" style={{color: 'var(--text-primary)', fontWeight: 500}}>{tokens}</span><div style={{fontSize: 9.5, color: 'var(--text-tertiary)'}}>tokens used</div></div>
            <div><span className="tnum" style={{color: 'var(--text-primary)', fontWeight: 500}}>{spend}</span><div style={{fontSize: 9.5, color: 'var(--text-tertiary)'}}>this week</div></div>
          </div>
        </div>
      </div>
    </div>
  );
}

function PopIconBtn({ theme, children, onClick }) {
  return (
    <button onClick={onClick} style={{
      width: 26, height: 22, borderRadius: 5, border: 0,
      background: 'transparent', cursor: 'pointer',
      color: 'var(--text-secondary)',
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      transition: 'background 0.1s',
    }}
    onMouseDown={(e) => e.currentTarget.style.background = theme === 'dark' ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)'}
    onMouseUp={(e) => e.currentTarget.style.background = 'transparent'}
    onMouseLeave={(e) => e.currentTarget.style.background = 'transparent'}>{children}</button>
  );
}

function PopMenuItem({ theme, icon, children, shortcut, danger, accent }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '6px 10px', borderRadius: 6,
      fontSize: 12.5, fontWeight: accent ? 500 : 400,
      color: danger ? 'var(--red)' : accent ? 'var(--accent)' : 'var(--text-primary)',
      cursor: 'default',
    }}>
      {icon && <span style={{opacity: 0.7, display: 'inline-flex'}}>{icon}</span>}
      <span>{children}</span>
      {shortcut && <span style={{marginLeft: 'auto', color: 'var(--text-tertiary)', fontSize: 11, fontFamily: 'var(--font-mono)'}}>{shortcut}</span>}
    </div>
  );
}

// Variant B — Dense compact: two cards side-by-side in one row
function PopV_DenseCompact({ theme = 'dark' }) {
  return (
    <MacPopover theme={theme} width={400}>
      <div style={{padding: '14px 14px 10px', display: 'flex', alignItems: 'center'}}>
        <span style={{fontSize: 13, fontWeight: 600}}>Codex · Claude Code</span>
        <span style={{fontSize: 11, color: 'var(--text-secondary)', marginLeft: 8}}>· just now</span>
        <span style={{marginLeft: 'auto', fontSize: 11, color: 'var(--text-secondary)', display: 'inline-flex', alignItems: 'center', gap: 4}}>
          <span style={{width: 6, height: 6, borderRadius: 3, background: 'var(--green)'}}/>
          live
        </span>
      </div>
      <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, padding: '0 12px 12px'}}>
        <ServiceCard theme={theme} name="Codex" cn="GPT-5 · Plus" color="#6C6C70" glyph={<CodexGlyph size={13} color="#fff"/>}
          value5h={0.42} valueWeek={0.31} reset="2h 18m" spend="$12.40"/>
        <ServiceCard theme={theme} name="Claude Code" cn="Sonnet · Max" color="#D97757" glyph={<CCGlyph size={13} color="#fff"/>}
          value5h={0.78} valueWeek={0.54} reset="1h 04m" spend="$48.10"/>
      </div>
      <div style={{
        padding: '8px 12px',
        borderTop: '0.5px solid var(--separator)',
        display: 'flex', gap: 6,
      }}>
        <PopBtn theme={theme}>Statistics · 统计</PopBtn>
        <PopBtn theme={theme}>Refresh · 刷新</PopBtn>
        <PopBtn theme={theme} icon>⋯</PopBtn>
      </div>
    </MacPopover>
  );
}

function ServiceCard({ theme, name, cn, color, glyph, value5h, valueWeek, reset, spend }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      borderRadius: 12,
      background: isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.025)',
      padding: '11px 12px',
      boxShadow: 'inset 0 0 0 0.5px ' + (isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'),
    }}>
      <div style={{display: 'flex', alignItems: 'center', gap: 6}}>
        <span style={{width: 18, height: 18, borderRadius: 5, background: color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center'}}>{glyph}</span>
        <span style={{fontSize: 12, fontWeight: 600}}>{name}</span>
      </div>
      <div style={{fontSize: 10, color: 'var(--text-tertiary)', marginTop: 1, marginLeft: 24}}>{cn}</div>
      <div style={{marginTop: 10, display: 'flex', alignItems: 'baseline', gap: 6}}>
        <span className="tnum" style={{fontSize: 26, fontWeight: 600, letterSpacing: -0.5, lineHeight: 1, color}}>{Math.round(value5h*100)}<span style={{fontSize: 13, opacity: 0.8}}>%</span></span>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)', letterSpacing: 0.2}}>5H</span>
      </div>
      <Bar value={value5h} color={color} height={4} radius={2}/>
      <div style={{marginTop: 9, display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontSize: 10, color: 'var(--text-secondary)'}}>
        <span>Week 周</span>
        <span className="tnum">{Math.round(valueWeek*100)}%</span>
      </div>
      <Bar value={valueWeek} color={color} height={3} radius={1.5}/>
      <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 10, fontSize: 10.5, color: 'var(--text-secondary)'}}>
        <span>↻ {reset}</span>
        <span className="tnum" style={{color: 'var(--text-primary)', fontWeight: 500}}>{spend}</span>
      </div>
    </div>
  );
}

function PopBtn({ theme, children, primary, icon }) {
  const isDark = theme === 'dark';
  return (
    <button style={{
      flex: icon ? '0 0 30px' : 1,
      height: 26, borderRadius: 7, border: 0,
      background: primary
        ? 'var(--accent)'
        : (isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)'),
      color: primary ? '#fff' : 'var(--text-primary)',
      fontFamily: 'inherit',
      fontSize: 11.5, fontWeight: 500,
      cursor: 'pointer',
      boxShadow: primary ? 'none' : '0 0.5px 0 ' + (isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)') + ' inset',
    }}>{children}</button>
  );
}

// Variant C — Vibrant accent + spark chart
function PopV_SparkChart({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <MacPopover theme={theme} width={360}>
      <div style={{padding: '14px 16px 8px', display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between'}}>
        <div>
          <div style={{fontSize: 11, color: 'var(--text-tertiary)', textTransform: 'uppercase', letterSpacing: 0.5}}>Last 24 hours · 过去 24 小时</div>
          <div style={{fontSize: 22, fontWeight: 600, letterSpacing: -0.4, marginTop: 2}} className="tnum">
            $60.50 <span style={{fontSize: 12, color: 'var(--green)', fontWeight: 500, marginLeft: 2}}>↑ 12%</span>
          </div>
        </div>
        <div style={{display: 'flex', gap: 4}}>
          <PopIconBtn theme={theme}><svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M14 8C14 11.3 11.3 14 8 14C5.5 14 3.3 12.5 2.3 10.3M2 8C2 4.7 4.7 2 8 2C10.5 2 12.7 3.5 13.7 5.7" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/><path d="M2 2.5V5.7H5.2M14 13.5V10.3H10.8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/></svg></PopIconBtn>
        </div>
      </div>
      <SparkBarChart theme={theme}/>
      <ServiceRow theme={theme} name="Codex" cn="GPT-5 · Plus" color="#6C6C70" glyph={<CodexGlyph size={13} color="#fff"/>}
        value5h={0.42} resetIn="2h 18m" spend="$12.40"/>
      <div style={{height: 0.5, background: 'var(--separator)', margin: '0 16px'}}/>
      <ServiceRow theme={theme} name="Claude Code" cn="Sonnet · Max" color="#D97757" glyph={<CCGlyph size={13} color="#fff"/>}
        value5h={0.78} resetIn="1h 04m" spend="$48.10"/>
      <div style={{
        padding: '8px 12px',
        borderTop: '0.5px solid var(--separator)',
        display: 'flex', gap: 6,
        background: isDark ? 'rgba(255,255,255,0.025)' : 'rgba(0,0,0,0.015)',
      }}>
        <PopBtn theme={theme} primary>Open Statistics</PopBtn>
        <PopBtn theme={theme} icon>⋯</PopBtn>
      </div>
    </MacPopover>
  );
}

function SparkBarChart({ theme }) {
  // 24 hourly bars, two colors stacked
  const isDark = theme === 'dark';
  const data = [
    [0.1,0.2],[0.05,0.1],[0,0.05],[0,0],[0.02,0],[0.1,0.05],
    [0.3,0.4],[0.5,0.6],[0.6,0.85],[0.4,0.9],[0.55,0.7],[0.7,0.85],
    [0.6,0.5],[0.4,0.55],[0.5,0.7],[0.45,0.6],[0.6,0.75],[0.55,0.8],
    [0.7,0.95],[0.6,0.7],[0.45,0.5],[0.35,0.4],[0.25,0.3],[0.18,0.22],
  ];
  return (
    <div style={{padding: '0 16px 12px'}}>
      <div style={{display: 'flex', alignItems: 'flex-end', gap: 2, height: 50}}>
        {data.map(([c, l], i) => (
          <div key={i} style={{flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', gap: 1, height: '100%'}}>
            <div style={{height: (l * 100) + '%', background: '#D97757', borderRadius: 1, opacity: 0.95}}></div>
            <div style={{height: (c * 100) + '%', background: isDark ? '#98989D' : '#6C6C70', borderRadius: 1, opacity: 0.95}}></div>
          </div>
        ))}
      </div>
      <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 9, color: 'var(--text-tertiary)', marginTop: 4, fontFamily: 'var(--font-mono)'}}>
        <span>00:00</span><span>06:00</span><span>12:00</span><span>18:00</span><span>now</span>
      </div>
    </div>
  );
}

function ServiceRow({ theme, name, cn, color, glyph, value5h, resetIn, spend }) {
  return (
    <div style={{padding: '11px 16px', display: 'flex', alignItems: 'center', gap: 12}}>
      <span style={{width: 28, height: 28, borderRadius: 8, background: color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center'}}>{glyph}</span>
      <div style={{flex: 1, minWidth: 0}}>
        <div style={{display: 'flex', alignItems: 'baseline', justifyContent: 'space-between'}}>
          <span style={{fontSize: 12.5, fontWeight: 600}}>{name}</span>
          <span className="tnum" style={{fontSize: 12.5, fontWeight: 600, color}}>{Math.round(value5h*100)}%</span>
        </div>
        <Bar value={value5h} color={color} height={4} radius={2}/>
        <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 4, fontSize: 10.5, color: 'var(--text-secondary)'}}>
          <span>{cn} · resets in {resetIn}</span>
          <span className="tnum">{spend}</span>
        </div>
      </div>
    </div>
  );
}

// Variant D — Card-Big-Stat: large numbers, low chrome
function PopV_BigStat({ theme = 'dark' }) {
  const isDark = theme === 'dark';
  return (
    <MacPopover theme={theme} width={320}>
      <BigStatBlock theme={theme} name="Codex" cn="OpenAI · Plus" color="#6C6C70" glyph={<CodexGlyph size={15} color="#fff"/>}
        value5h={0.42} weekVal={0.31} resetIn="2h 18m" tokensUsed="184k" tokensCap="440k" spend="$12.40"/>
      <div style={{height: 0.5, background: 'var(--separator)', margin: '0 14px'}}/>
      <BigStatBlock theme={theme} name="Claude Code" cn="Anthropic · Max 20×" color="#D97757" glyph={<CCGlyph size={15} color="#fff"/>}
        value5h={0.78} weekVal={0.54} resetIn="1h 04m" tokensUsed="6.2M" tokensCap="8M" spend="$48.10"/>
      <div style={{
        padding: '8px 10px',
        borderTop: '0.5px solid var(--separator)',
        display: 'flex', alignItems: 'center', gap: 4,
        fontSize: 11.5,
      }}>
        <PopMenuItem theme={theme}>Statistics… · 统计</PopMenuItem>
        <PopMenuItem theme={theme}>Preferences… · 偏好</PopMenuItem>
        <div style={{marginLeft: 'auto'}}>
          <PopIconBtn theme={theme}><svg width="14" height="14" viewBox="0 0 16 16" fill="none"><path d="M14 8C14 11.3 11.3 14 8 14C5.5 14 3.3 12.5 2.3 10.3M2 8C2 4.7 4.7 2 8 2C10.5 2 12.7 3.5 13.7 5.7" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/><path d="M2 2.5V5.7H5.2M14 13.5V10.3H10.8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/></svg></PopIconBtn>
        </div>
      </div>
    </MacPopover>
  );
}

function BigStatBlock({ theme, name, cn, color, glyph, value5h, weekVal, resetIn, tokensUsed, tokensCap, spend }) {
  return (
    <div style={{padding: '14px 16px'}}>
      <div style={{display: 'flex', alignItems: 'center', gap: 9, marginBottom: 10}}>
        <span style={{width: 22, height: 22, borderRadius: 6, background: color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center'}}>{glyph}</span>
        <span style={{fontSize: 13, fontWeight: 600}}>{name}</span>
        <span style={{fontSize: 11, color: 'var(--text-tertiary)'}}>{cn}</span>
        <span style={{marginLeft: 'auto', fontSize: 10, color: 'var(--text-tertiary)', fontFamily: 'var(--font-mono)'}}>↻ {resetIn}</span>
      </div>
      <div style={{display: 'flex', alignItems: 'flex-end', gap: 16}}>
        <div style={{lineHeight: 0.95}}>
          <div className="tnum" style={{fontSize: 38, fontWeight: 600, letterSpacing: -1, color}}>{Math.round(value5h * 100)}<span style={{fontSize: 18, opacity: 0.75}}>%</span></div>
          <div style={{fontSize: 10, color: 'var(--text-tertiary)', marginTop: 4, letterSpacing: 0.3}}>5-HOUR · 五小时</div>
        </div>
        <div style={{flex: 1, paddingBottom: 4}}>
          <Bar value={value5h} color={color} height={6} radius={3}/>
          <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 10.5, color: 'var(--text-secondary)', marginTop: 8}}>
            <span className="tnum"><span style={{color: 'var(--text-primary)', fontWeight: 500}}>{tokensUsed}</span> / {tokensCap}</span>
            <span className="tnum" style={{color: 'var(--text-primary)', fontWeight: 500}}>{spend}</span>
          </div>
          <div style={{display: 'flex', justifyContent: 'space-between', fontSize: 9.5, color: 'var(--text-tertiary)', marginTop: 1}}>
            <span>tokens · 令牌</span><span>this week · 本周</span>
          </div>
        </div>
      </div>
      <div style={{marginTop: 12, display: 'flex', alignItems: 'center', gap: 8}}>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)', letterSpacing: 0.2, width: 38}}>WEEK</span>
        <div style={{flex: 1}}><Bar value={weekVal} color={color} height={3} radius={1.5}/></div>
        <span className="tnum" style={{fontSize: 10.5, color: 'var(--text-secondary)'}}>{Math.round(weekVal*100)}%</span>
      </div>
    </div>
  );
}

Object.assign(window, {
  PopV_VerticalList, PopV_DenseCompact, PopV_SparkChart, PopV_BigStat,
  ServiceHeader, StatRow, ServiceBlock, PopIconBtn, PopMenuItem, PopBtn,
  ServiceCard, ServiceRow, BigStatBlock, SparkBarChart,
});
