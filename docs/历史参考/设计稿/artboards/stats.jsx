// Full statistics window variants. Big window with sidebar + charts.

// Shared data: 30-day stacked bar chart
const DAILY = [
  [1.2, 4.8], [0.8, 3.2], [1.5, 5.1], [2.0, 4.5], [1.3, 6.2], [0.5, 2.1], [0.2, 1.0],
  [1.8, 5.5], [2.2, 6.8], [1.9, 5.9], [1.6, 4.2], [2.5, 7.1], [1.1, 3.8], [0.7, 2.5],
  [1.4, 4.7], [2.1, 6.3], [1.7, 5.0], [2.3, 6.6], [1.9, 5.8], [1.5, 4.4], [0.9, 3.0],
  [2.6, 7.4], [2.0, 6.0], [1.8, 5.3], [2.4, 6.9], [1.6, 4.8], [1.2, 3.6], [0.8, 2.8],
  [2.2, 6.5], [1.4, 4.1],
];
const HOURS = ['00','03','06','09','12','15','18','21'];

// Variant A — Dashboard with sidebar, ring overview, stacked bar timeline
function StatsV_Dashboard({ theme = 'dark', preset = '30d' }) {
  return (
    <MacWindow theme={theme} toolbar={<StatsToolbar theme={theme} preset={preset}/>}>
      <div style={{display: 'flex', height: '100%', background: 'var(--window-bg)'}}>
        <StatsSidebar theme={theme} preset={preset}/>
        <div className="no-scrollbar" style={{flex: 1, overflowY: 'auto', padding: 20}}>
          {/* Top KPI row */}
          <div style={{display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 18}}>
            <KPICard theme={theme} label="Total tokens" cn="总令牌" value="48.2M" delta="+12.4%" deltaPos accent="var(--text-primary)"/>
            <KPICard theme={theme} label="Total spend" cn="总花费" value="$1,284.50" delta="+8.1%" deltaPos accent="var(--text-primary)"/>
            <KPICard theme={theme} label="Codex" cn="OpenAI" value="$412.30" delta="-2.3%" accent="#6C6C70"/>
            <KPICard theme={theme} label="Claude Code" cn="Anthropic" value="$872.20" delta="+18.6%" deltaPos accent="#D97757"/>
          </div>

          {/* Main chart */}
          <Panel theme={theme} title="Daily usage" cn="每日用量" right={
            <div style={{display: 'flex', gap: 4}}>
              <ChartLegend color="#98989D" label="Codex"/>
              <ChartLegend color="#D97757" label="Claude"/>
            </div>
          }>
            <StackedBarChart data={DAILY} height={160}/>
            <DateAxis days={30}/>
          </Panel>

          <div style={{display: 'grid', gridTemplateColumns: '1.4fr 1fr', gap: 12, marginTop: 12}}>
            <Panel theme={theme} title="By service" cn="按服务">
              <ServiceCompareRow theme={theme} name="Codex" cn="OpenAI · GPT-5" color="#6C6C70" value="$412.30" pct={0.32} tokens="18.4M"/>
              <ServiceCompareRow theme={theme} name="Claude Code" cn="Anthropic · Sonnet 4.5" color="#D97757" value="$872.20" pct={0.68} tokens="29.8M"/>
            </Panel>
            <Panel theme={theme} title="Current limits" cn="当前限额">
              <LimitRing theme={theme} label="Codex 5h" value={0.42} reset="2h 18m" color="#6C6C70"/>
              <LimitRing theme={theme} label="Codex Week" value={0.31} reset="3d 12h" color="#6C6C70"/>
              <LimitRing theme={theme} label="Claude 5h" value={0.78} reset="1h 04m" color="#D97757"/>
              <LimitRing theme={theme} label="Claude Week" value={0.54} reset="3d 12h" color="#D97757"/>
            </Panel>
          </div>
        </div>
      </div>
    </MacWindow>
  );
}

function StatsToolbar({ theme, preset }) {
  const isDark = theme === 'dark';
  return (
    <>
      <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
        <span style={{fontSize: 13, fontWeight: 600}}>Statistics</span>
        <span style={{fontSize: 11, color: 'var(--text-secondary)'}}>用量统计</span>
      </div>
      <div style={{marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 6}}>
        <SegmentedControl theme={theme} options={['Today', 'Week', 'Month', '7d', '30d', 'All', 'Custom']} active={preset === '30d' ? '30d' : preset}/>
      </div>
    </>
  );
}

function SegmentedControl({ theme, options, active }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      display: 'inline-flex',
      padding: 2, borderRadius: 7,
      background: isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
      gap: 2,
    }}>
      {options.map(o => (
        <button key={o} style={{
          padding: '3px 10px', height: 22,
          borderRadius: 5, border: 0, cursor: 'pointer',
          background: o === active
            ? (isDark ? 'rgba(120,120,128,0.55)' : '#fff')
            : 'transparent',
          color: 'var(--text-primary)',
          fontFamily: 'inherit', fontSize: 11.5, fontWeight: o === active ? 600 : 400,
          letterSpacing: -0.05,
          boxShadow: o === active ? '0 0.5px 2px rgba(0,0,0,0.18)' : 'none',
        }}>{o}</button>
      ))}
    </div>
  );
}

function StatsSidebar({ theme, preset }) {
  const isDark = theme === 'dark';
  return (
    <div className="no-scrollbar" style={{
      width: 200, flexShrink: 0,
      borderRight: '0.5px solid var(--separator)',
      background: isDark ? 'rgba(38,38,40,0.5)' : 'rgba(246,246,247,0.5)',
      backdropFilter: 'saturate(180%) blur(20px)',
      WebkitBackdropFilter: 'saturate(180%) blur(20px)',
      padding: '14px 12px',
      overflowY: 'auto',
      display: 'flex', flexDirection: 'column', gap: 16,
    }}>
      <SidebarGroup title="Range" cn="时间范围">
        {[
          ['Today', '今天'],
          ['This week', '本周'],
          ['This month', '本月'],
          ['Last 7 days', '最近 7 天'],
          ['Last 30 days', '最近 30 天'],
          ['All time', '全部'],
          ['Custom…', '自定义…'],
        ].map(([en, cn], i) => (
          <SidebarItem key={en} en={en} cn={cn} active={i === 4 && preset === '30d'} icon={
            <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><rect x="2" y="3.5" width="12" height="11" rx="2" stroke="currentColor" strokeWidth="1.3"/><path d="M2 6.5H14M5.5 2V5M10.5 2V5" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round"/></svg>
          }/>
        ))}
      </SidebarGroup>
      <SidebarGroup title="Service" cn="服务">
        <SidebarItem en="All" cn="全部" active dot={null}/>
        <SidebarItem en="Codex" cn="OpenAI" dot="#6C6C70"/>
        <SidebarItem en="Claude Code" cn="Anthropic" dot="#D97757"/>
      </SidebarGroup>
      <SidebarGroup title="View" cn="视图">
        <SidebarItem en="Overview" cn="概览" active icon={
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><rect x="2" y="2" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.3"/><rect x="9" y="2" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.3"/><rect x="2" y="9" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.3"/><rect x="9" y="9" width="5" height="5" rx="1" stroke="currentColor" strokeWidth="1.3"/></svg>
        }/>
        <SidebarItem en="Timeline" cn="时间线" icon={
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M2 13L5 9L8 11L11 5L14 8" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/></svg>
        }/>
        <SidebarItem en="Breakdown" cn="明细" icon={
          <svg width="13" height="13" viewBox="0 0 16 16" fill="none"><path d="M3 4H13M3 8H13M3 12H9" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/></svg>
        }/>
      </SidebarGroup>
    </div>
  );
}

function SidebarGroup({ title, cn, children }) {
  return (
    <div>
      <div style={{
        fontSize: 10, fontWeight: 600,
        color: 'var(--text-tertiary)',
        letterSpacing: 0.4, textTransform: 'uppercase',
        padding: '0 6px 4px',
      }}>{title} · {cn}</div>
      <div style={{display: 'flex', flexDirection: 'column', gap: 1}}>{children}</div>
    </div>
  );
}

function SidebarItem({ en, cn, active, icon, dot }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '5px 8px', borderRadius: 6,
      background: active ? 'var(--accent)' : 'transparent',
      color: active ? '#fff' : 'var(--text-primary)',
      fontSize: 12, fontWeight: 500,
    }}>
      {icon && <span style={{opacity: active ? 1 : 0.7, display: 'inline-flex'}}>{icon}</span>}
      {dot !== undefined && dot !== null && <span style={{width: 8, height: 8, borderRadius: 2, background: dot, flexShrink: 0}}/>}
      {dot === null && <span style={{width: 8, height: 8, flexShrink: 0}}/>}
      <span>{en}</span>
      <span style={{marginLeft: 'auto', fontSize: 10.5, opacity: active ? 0.75 : 0.5}}>{cn}</span>
    </div>
  );
}

function Panel({ theme, title, cn, right, children, style }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      borderRadius: 12,
      background: isDark ? 'rgba(60,60,63,0.4)' : '#fff',
      boxShadow: 'inset 0 0 0 0.5px ' + (isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'),
      padding: 16,
      ...style,
    }}>
      <div style={{display: 'flex', alignItems: 'center', marginBottom: 12}}>
        <div style={{display: 'flex', flexDirection: 'column', lineHeight: 1.1}}>
          <span style={{fontSize: 12.5, fontWeight: 600}}>{title}</span>
          {cn && <span style={{fontSize: 10.5, color: 'var(--text-tertiary)'}}>{cn}</span>}
        </div>
        {right && <div style={{marginLeft: 'auto'}}>{right}</div>}
      </div>
      {children}
    </div>
  );
}

function ChartLegend({ color, label }) {
  return (
    <span style={{display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11, color: 'var(--text-secondary)', padding: '0 6px'}}>
      <span style={{width: 9, height: 9, borderRadius: 2, background: color}}/>
      {label}
    </span>
  );
}

function KPICard({ theme, label, cn, value, delta, deltaPos, accent }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      borderRadius: 10,
      background: isDark ? 'rgba(60,60,63,0.4)' : '#fff',
      boxShadow: 'inset 0 0 0 0.5px ' + (isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'),
      padding: '11px 14px',
    }}>
      <div style={{fontSize: 11, color: 'var(--text-secondary)', display: 'flex', alignItems: 'baseline', gap: 4}}>
        {accent && accent !== 'var(--text-primary)' && <span style={{width: 6, height: 6, borderRadius: 1.5, background: accent}}/>}
        <span>{label}</span>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)'}}>{cn}</span>
      </div>
      <div style={{display: 'flex', alignItems: 'baseline', gap: 8, marginTop: 4}}>
        <span className="tnum" style={{fontSize: 22, fontWeight: 600, letterSpacing: -0.5, color: accent}}>{value}</span>
        <span className="tnum" style={{fontSize: 11, fontWeight: 500, color: deltaPos ? 'var(--green)' : 'var(--red)'}}>{deltaPos ? '↑' : '↓'} {delta.replace(/^[+-]/, '').replace('%','')}<span style={{opacity: 0.8}}>%</span></span>
      </div>
    </div>
  );
}

function StackedBarChart({ data, height = 140 }) {
  const max = Math.max(...data.map(([a, b]) => a + b)) * 1.1;
  return (
    <div style={{display: 'flex', alignItems: 'flex-end', gap: 3, height, padding: '0 2px'}}>
      {data.map(([c, l], i) => (
        <div key={i} style={{flex: 1, height: '100%', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', gap: 1}}>
          <div style={{height: ((l / max) * 100) + '%', background: '#D97757', borderRadius: '2px 2px 0 0', minHeight: 1}}/>
          <div style={{height: ((c / max) * 100) + '%', background: '#98989D', borderRadius: '0 0 2px 2px', minHeight: 1}}/>
        </div>
      ))}
    </div>
  );
}

function DateAxis({ days }) {
  // Show start, week marks, today
  return (
    <div style={{display: 'flex', justifyContent: 'space-between', marginTop: 6, fontSize: 10, color: 'var(--text-tertiary)', fontFamily: 'var(--font-mono)'}}>
      <span>Jul 16</span>
      <span>Jul 23</span>
      <span>Jul 30</span>
      <span>Aug 06</span>
      <span>Today</span>
    </div>
  );
}

function ServiceCompareRow({ theme, name, cn, color, value, pct, tokens }) {
  return (
    <div style={{padding: '8px 0'}}>
      <div style={{display: 'flex', alignItems: 'baseline'}}>
        <span style={{width: 8, height: 8, borderRadius: 2, background: color, marginRight: 8}}/>
        <span style={{fontSize: 12, fontWeight: 600}}>{name}</span>
        <span style={{fontSize: 10.5, color: 'var(--text-tertiary)', marginLeft: 6}}>{cn}</span>
        <span className="tnum" style={{marginLeft: 'auto', fontSize: 13, fontWeight: 600}}>{value}</span>
      </div>
      <div style={{marginTop: 6, marginLeft: 16}}><Bar value={pct} color={color} height={5} radius={2.5}/></div>
      <div style={{marginTop: 4, marginLeft: 16, display: 'flex', justifyContent: 'space-between', fontSize: 10.5, color: 'var(--text-secondary)'}}>
        <span className="tnum">{tokens} tokens</span>
        <span className="tnum">{Math.round(pct*100)}% of spend</span>
      </div>
    </div>
  );
}

function LimitRing({ theme, label, value, reset, color }) {
  return (
    <div style={{display: 'flex', alignItems: 'center', gap: 11, padding: '7px 0'}}>
      <Ring size={32} stroke={4} value={value} color={color} track="currentColor">
        <span className="tnum" style={{fontSize: 9.5, fontWeight: 600}}>{Math.round(value*100)}</span>
      </Ring>
      <div style={{flex: 1, lineHeight: 1.15}}>
        <div style={{fontSize: 12, fontWeight: 500}}>{label}</div>
        <div style={{fontSize: 10.5, color: 'var(--text-secondary)'}}>resets in {reset}</div>
      </div>
    </div>
  );
}

// Variant B — Timeline detail: hourly line/area chart
function StatsV_Timeline({ theme = 'dark' }) {
  return (
    <MacWindow theme={theme} toolbar={<StatsToolbar theme={theme} preset="7d"/>}>
      <div style={{display: 'flex', height: '100%'}}>
        <StatsSidebar theme={theme} preset="7d"/>
        <div className="no-scrollbar" style={{flex: 1, overflowY: 'auto', padding: 20}}>
          <Panel theme={theme} title="Tokens · hourly" cn="按小时令牌" right={
            <div style={{display: 'flex', gap: 4}}>
              <ChartLegend color="#98989D" label="Codex"/>
              <ChartLegend color="#D97757" label="Claude"/>
            </div>
          }>
            <AreaLineChart theme={theme} height={220}/>
          </Panel>
          <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 12}}>
            <Panel theme={theme} title="Hourly pattern" cn="每小时分布">
              <HourlyHeatmap theme={theme}/>
            </Panel>
            <Panel theme={theme} title="Spend split" cn="花费占比">
              <PieSplit/>
            </Panel>
          </div>
        </div>
      </div>
    </MacWindow>
  );
}

function AreaLineChart({ theme, height = 200 }) {
  const isDark = theme === 'dark';
  // Generate two paths
  const pts = 48;
  const codex = Array.from({length: pts}, (_, i) => {
    const t = i / pts;
    return 0.15 + 0.3 * Math.sin(t * 6.28 * 2) + 0.1 * Math.sin(t * 13) + 0.2;
  });
  const claude = codex.map((c, i) => c + 0.3 + 0.4 * Math.sin(i * 0.7) * 0.3 + 0.2);
  const max = Math.max(...claude) * 1.15;
  const xy = (arr) => arr.map((v, i) => [i / (pts - 1) * 100, 100 - (v / max) * 100]);
  const toPath = (pts) => pts.map((p, i) => (i ? 'L' : 'M') + p[0] + ',' + p[1]).join(' ');
  const toAreaPath = (pts) => toPath(pts) + ` L100,100 L0,100 Z`;
  const codexPts = xy(codex);
  const claudePts = xy(claude);
  return (
    <svg width="100%" viewBox="0 0 100 100" preserveAspectRatio="none" style={{height, display: 'block'}}>
      <defs>
        <linearGradient id="grad-c" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#98989D" stopOpacity="0.4"/>
          <stop offset="100%" stopColor="#98989D" stopOpacity="0"/>
        </linearGradient>
        <linearGradient id="grad-l" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="#D97757" stopOpacity="0.4"/>
          <stop offset="100%" stopColor="#D97757" stopOpacity="0"/>
        </linearGradient>
      </defs>
      {/* gridlines */}
      {[20, 40, 60, 80].map(y => (
        <line key={y} x1="0" y1={y} x2="100" y2={y} stroke={isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'} strokeWidth="0.2" vectorEffect="non-scaling-stroke"/>
      ))}
      <path d={toAreaPath(claudePts)} fill="url(#grad-l)"/>
      <path d={toPath(claudePts)} stroke="#D97757" strokeWidth="1.6" fill="none" vectorEffect="non-scaling-stroke"/>
      <path d={toAreaPath(codexPts)} fill="url(#grad-c)"/>
      <path d={toPath(codexPts)} stroke="#98989D" strokeWidth="1.6" fill="none" vectorEffect="non-scaling-stroke"/>
    </svg>
  );
}

function HourlyHeatmap({ theme }) {
  const isDark = theme === 'dark';
  // 7 days x 24 hours
  return (
    <div style={{display: 'flex', flexDirection: 'column', gap: 2}}>
      {['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map((d, di) => (
        <div key={d} style={{display: 'flex', alignItems: 'center', gap: 6}}>
          <span style={{fontSize: 9.5, width: 22, color: 'var(--text-tertiary)', fontFamily: 'var(--font-mono)'}}>{d}</span>
          <div style={{display: 'flex', gap: 1.5, flex: 1}}>
            {Array.from({length: 24}, (_, h) => {
              // intensity model
              let v = 0;
              if (h >= 9 && h <= 18) v = 0.4 + Math.random() * 0.5;
              else if (h >= 19 && h <= 23) v = 0.1 + Math.random() * 0.4;
              else v = Math.random() * 0.15;
              if (di === 5 || di === 6) v *= 0.3; // weekend
              return (
                <div key={h} style={{
                  flex: 1, height: 14, borderRadius: 2,
                  background: `rgba(217, 119, 87, ${v.toFixed(2)})`,
                  boxShadow: v < 0.1 ? `inset 0 0 0 0.5px ${isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.05)'}` : 'none',
                }}/>
              );
            })}
          </div>
        </div>
      ))}
      <div style={{display: 'flex', gap: 6, marginTop: 4, fontSize: 9, color: 'var(--text-tertiary)', fontFamily: 'var(--font-mono)'}}>
        <span style={{width: 22}}></span>
        <div style={{display: 'flex', justifyContent: 'space-between', flex: 1, paddingLeft: 2, paddingRight: 2}}>
          <span>0</span><span>6</span><span>12</span><span>18</span><span>23</span>
        </div>
      </div>
    </div>
  );
}

function PieSplit() {
  // Donut
  const r = 38, stroke = 22;
  const c = 2 * Math.PI * r;
  const codexPct = 0.32;
  return (
    <div style={{display: 'flex', alignItems: 'center', gap: 18, padding: '6px 0'}}>
      <svg width="110" height="110" viewBox="0 0 110 110">
        <circle cx="55" cy="55" r={r} fill="none" stroke="#D97757" strokeWidth={stroke}/>
        <circle cx="55" cy="55" r={r} fill="none" stroke="#98989D" strokeWidth={stroke}
          strokeDasharray={`${c * codexPct} ${c}`}
          transform="rotate(-90 55 55)"/>
        <text x="55" y="56" textAnchor="middle" dominantBaseline="middle" fontSize="14" fontWeight="600" fontFamily="-apple-system" fill="currentColor">$1,284</text>
        <text x="55" y="68" textAnchor="middle" dominantBaseline="middle" fontSize="8" fill="currentColor" opacity="0.5" fontFamily="-apple-system">total · 总计</text>
      </svg>
      <div style={{flex: 1, display: 'flex', flexDirection: 'column', gap: 8}}>
        <PieRow color="#98989D" label="Codex" cn="OpenAI" value="$412.30" pct="32%"/>
        <PieRow color="#D97757" label="Claude Code" cn="Anthropic" value="$872.20" pct="68%"/>
      </div>
    </div>
  );
}

function PieRow({ color, label, cn, value, pct }) {
  return (
    <div>
      <div style={{display: 'flex', alignItems: 'baseline', gap: 6}}>
        <span style={{width: 8, height: 8, borderRadius: 2, background: color}}/>
        <span style={{fontSize: 12, fontWeight: 600}}>{label}</span>
        <span style={{fontSize: 10, color: 'var(--text-tertiary)'}}>{cn}</span>
      </div>
      <div style={{display: 'flex', alignItems: 'baseline', gap: 6, marginLeft: 14, marginTop: 1}}>
        <span className="tnum" style={{fontSize: 13.5, fontWeight: 600}}>{value}</span>
        <span className="tnum" style={{fontSize: 10.5, color: 'var(--text-secondary)'}}>{pct}</span>
      </div>
    </div>
  );
}

Object.assign(window, {
  StatsV_Dashboard, StatsV_Timeline,
  StatsToolbar, SegmentedControl, StatsSidebar, SidebarItem, SidebarGroup,
  Panel, KPICard, StackedBarChart, AreaLineChart, HourlyHeatmap, PieSplit, ChartLegend,
  ServiceCompareRow, LimitRing, DateAxis, DAILY,
});
