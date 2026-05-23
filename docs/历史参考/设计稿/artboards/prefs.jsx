// Preferences window + Onboarding screens

// Preferences --------------------------------------------------------------
function PrefsV_Main({ theme = 'dark' }) {
  return (
    <MacWindow theme={theme} toolbar={<PrefsToolbar theme={theme}/>}>
      <div className="no-scrollbar" style={{padding: '20px 28px', overflowY: 'auto', height: '100%'}}>
        <PrefsGroup theme={theme} title="Accounts" cn="账号" desc="Auto-detected on your Mac. Toggle which services to display." cnDesc="自动检测，自行勾选要显示的">
          <AccountRow theme={theme} on
            color="#6C6C70" glyph={<CodexGlyph size={14} color="#fff"/>}
            name="Codex" cn="OpenAI · GPT-5"
            sub="user@example.com · Plus" status="Connected · 已连接"/>
          <AccountRow theme={theme} on
            color="#D97757" glyph={<CCGlyph size={14} color="#fff"/>}
            name="Claude Code" cn="Anthropic · Sonnet 4.5"
            sub="user@example.com · Max 20×" status="Connected · 已连接"/>
        </PrefsGroup>

        <PrefsGroup theme={theme} title="Menu Bar" cn="菜单栏" desc="What appears next to the icon." cnDesc="图标旁显示什么">
          <PrefsRow theme={theme} label="Show in menu bar" cn="显示在菜单栏">
            <Toggle on/>
          </PrefsRow>
          <PrefsRow theme={theme} label="Display" cn="显示内容">
            <DropdownPill theme={theme} value="Icon + Percentage · 图标 + 百分比"/>
          </PrefsRow>
          <PrefsRow theme={theme} label="Show service" cn="显示服务">
            <CheckboxGroup theme={theme}>
              <CheckItem checked label="Codex"/>
              <CheckItem checked label="Claude Code"/>
            </CheckboxGroup>
          </PrefsRow>
          <PrefsRow theme={theme} label="Quota period" cn="额度周期" desc="Which window to display in the menu bar." cnDesc="菜单栏图标显示的是哪个窗口">
            <RadioGroup theme={theme}>
              <RadioItem checked label="5-hour · 5 小时"/>
              <RadioItem label="Weekly · 周额度"/>
              <RadioItem label="Both, cycle · 两者轮播"/>
            </RadioGroup>
          </PrefsRow>
        </PrefsGroup>

        <PrefsGroup theme={theme} title="Floating HUD" cn="桌面悬浮窗" desc="A small always-on-top window pinned to your desktop." cnDesc="桌面常驻的小悬浮窗">
          <PrefsRow theme={theme} label="Show floating window" cn="显示悬浮窗"><Toggle on/></PrefsRow>
          <PrefsRow theme={theme} label="Show service" cn="显示哪些">
            <CheckboxGroup theme={theme}>
              <CheckItem checked label="Codex"/>
              <CheckItem checked label="Claude Code"/>
            </CheckboxGroup>
          </PrefsRow>
          <PrefsRow theme={theme} label="Style" cn="样式">
            <DropdownPill theme={theme} value="Two-row pill · 两行胶囊"/>
          </PrefsRow>
          <PrefsRow theme={theme} label="Position" cn="位置">
            <DropdownPill theme={theme} value="Top right · 右上"/>
          </PrefsRow>
          <PrefsRow theme={theme} label="Opacity when idle" cn="空闲时透明度">
            <Slider value={0.7}/>
          </PrefsRow>
        </PrefsGroup>

        <PrefsGroup theme={theme} title="Refresh" cn="刷新" desc="How often the app polls usage in the background." cnDesc="后台轮询用量的频率">
          <PrefsRow theme={theme} label="Auto refresh" cn="自动刷新"><Toggle on/></PrefsRow>
          <PrefsRow theme={theme} label="Interval" cn="间隔">
            <DropdownPill theme={theme} value="Every 2 minutes · 每 2 分钟"/>
          </PrefsRow>
          <PrefsRow theme={theme} label="Last refresh" cn="上次刷新">
            <span style={{fontSize: 11.5, color: 'var(--text-secondary)'}} className="tnum">14:42:08 · 32s ago</span>
          </PrefsRow>
        </PrefsGroup>

        <PrefsGroup theme={theme} title="General" cn="通用">
          <PrefsRow theme={theme} label="Launch at login" cn="开机自动启动"><Toggle on/></PrefsRow>
          <PrefsRow theme={theme} label="Show in Dock" cn="在 Dock 中显示"><Toggle/></PrefsRow>
          <PrefsRow theme={theme} label="Language" cn="语言">
            <DropdownPill theme={theme} value="System · 跟随系统"/>
          </PrefsRow>
        </PrefsGroup>

        <div style={{marginTop: 24, padding: '12px 0', display: 'flex', alignItems: 'center', gap: 8, color: 'var(--text-tertiary)', fontSize: 11}}>
          <span>cc-bar 1.0 · made with Liquid Glass</span>
          <span style={{marginLeft: 'auto'}}>Help · Privacy · Quit</span>
        </div>
      </div>
    </MacWindow>
  );
}

function PrefsToolbar({ theme }) {
  return (
    <>
      <div style={{display: 'flex', alignItems: 'center', gap: 10}}>
        <span style={{fontSize: 13, fontWeight: 600}}>Preferences</span>
        <span style={{fontSize: 11, color: 'var(--text-secondary)'}}>偏好设置</span>
      </div>
    </>
  );
}

function PrefsGroup({ theme, title, cn, desc, cnDesc, children }) {
  const isDark = theme === 'dark';
  return (
    <div style={{marginBottom: 22}}>
      <div style={{padding: '0 4px 8px'}}>
        <div style={{fontSize: 12, fontWeight: 600, letterSpacing: -0.05}}>{title} · {cn}</div>
        {desc && <div style={{fontSize: 10.5, color: 'var(--text-tertiary)', marginTop: 2}}>{desc} · {cnDesc}</div>}
      </div>
      <div style={{
        borderRadius: 10,
        background: isDark ? 'rgba(60,60,63,0.4)' : '#fff',
        boxShadow: 'inset 0 0 0 0.5px ' + (isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'),
        overflow: 'hidden',
      }}>{children}</div>
    </div>
  );
}

function PrefsRow({ theme, label, cn, desc, cnDesc, children }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '10px 14px',
      borderTop: '0.5px solid var(--separator)',
    }}>
      <div style={{flex: 1, lineHeight: 1.25}}>
        <div style={{fontSize: 12.5, fontWeight: 400}}>{label}<span style={{color: 'var(--text-tertiary)', marginLeft: 6, fontSize: 11}}>{cn}</span></div>
        {desc && <div style={{fontSize: 10.5, color: 'var(--text-tertiary)', marginTop: 1}}>{desc}</div>}
      </div>
      <div style={{flexShrink: 0}}>{children}</div>
    </div>
  );
}

function AccountRow({ theme, on, color, glyph, name, cn, sub, status }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 11,
      padding: '12px 14px',
      borderTop: '0.5px solid var(--separator)',
    }}>
      <span style={{width: 28, height: 28, borderRadius: 7, background: color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center'}}>{glyph}</span>
      <div style={{flex: 1, lineHeight: 1.2}}>
        <div style={{fontSize: 12.5, fontWeight: 600}}>{name} <span style={{color: 'var(--text-tertiary)', fontWeight: 400, marginLeft: 4}}>· {cn}</span></div>
        <div style={{fontSize: 10.5, color: 'var(--text-secondary)'}}>{sub}</div>
      </div>
      <div style={{display: 'flex', alignItems: 'center', gap: 8}}>
        <span style={{display: 'inline-flex', alignItems: 'center', gap: 4, fontSize: 10.5, color: 'var(--green)'}}>
          <span style={{width: 6, height: 6, borderRadius: 3, background: 'var(--green)'}}/>
          {status}
        </span>
        <Toggle on={on}/>
      </div>
    </div>
  );
}

function Toggle({ on }) {
  return (
    <span style={{
      display: 'inline-block', width: 32, height: 20,
      borderRadius: 11,
      background: on ? 'var(--green)' : 'var(--fill)',
      position: 'relative',
      transition: 'background 0.15s',
      boxShadow: on ? 'none' : 'inset 0 0 0 0.5px var(--separator-strong)',
    }}>
      <span style={{
        position: 'absolute',
        top: 2, left: on ? 14 : 2,
        width: 16, height: 16, borderRadius: 8,
        background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.3), 0 0 0 0.5px rgba(0,0,0,0.05)',
        transition: 'left 0.15s',
      }}/>
    </span>
  );
}

function DropdownPill({ theme, value }) {
  const isDark = theme === 'dark';
  return (
    <button style={{
      height: 22, padding: '0 8px',
      borderRadius: 6, border: 0,
      background: isDark ? 'rgba(120,120,128,0.36)' : '#fff',
      boxShadow: isDark
        ? 'inset 0 0 0 0.5px rgba(255,255,255,0.08), 0 0.5px 1px rgba(0,0,0,0.2)'
        : 'inset 0 0 0 0.5px rgba(0,0,0,0.16), 0 0.5px 1.5px rgba(0,0,0,0.06)',
      color: 'var(--text-primary)',
      fontFamily: 'inherit', fontSize: 11.5, fontWeight: 400,
      display: 'inline-flex', alignItems: 'center', gap: 6,
      cursor: 'default',
    }}>
      {value}
      <svg width="9" height="9" viewBox="0 0 10 10" fill="none">
        <path d="M2 4L5 1.5L8 4M2 6L5 8.5L8 6" stroke="currentColor" strokeWidth="1.3" strokeLinecap="round" strokeLinejoin="round" opacity="0.7"/>
      </svg>
    </button>
  );
}

function CheckboxGroup({ theme, children }) {
  return <div style={{display: 'flex', flexDirection: 'column', gap: 4}}>{children}</div>;
}

function CheckItem({ checked, label }) {
  return (
    <label style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5}}>
      <span style={{
        width: 13, height: 13, borderRadius: 3.5,
        background: checked ? 'var(--accent)' : 'transparent',
        boxShadow: checked ? 'none' : 'inset 0 0 0 1px var(--separator-strong)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {checked && <svg width="10" height="8" viewBox="0 0 10 8" fill="none"><path d="M1 4L3.5 6.5L9 1" stroke="#fff" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/></svg>}
      </span>
      {label}
    </label>
  );
}

function RadioGroup({ theme, children }) {
  return <div style={{display: 'flex', flexDirection: 'column', gap: 4}}>{children}</div>;
}

function RadioItem({ checked, label }) {
  return (
    <label style={{display: 'inline-flex', alignItems: 'center', gap: 6, fontSize: 11.5}}>
      <span style={{
        width: 13, height: 13, borderRadius: 7,
        background: checked ? 'var(--accent)' : 'transparent',
        boxShadow: checked ? 'inset 0 0 0 3.5px #fff, inset 0 0 0 4px var(--accent)' : 'inset 0 0 0 1px var(--separator-strong)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
      }}/>
      {label}
    </label>
  );
}

function Slider({ value = 0.5 }) {
  return (
    <div style={{width: 140, height: 14, position: 'relative', display: 'flex', alignItems: 'center'}}>
      <div style={{flex: 1, height: 3, borderRadius: 1.5, background: 'var(--fill)'}}>
        <div style={{width: (value*100) + '%', height: '100%', borderRadius: 1.5, background: 'var(--accent)'}}/>
      </div>
      <span style={{
        position: 'absolute', left: 'calc(' + (value*100) + '% - 7px)',
        width: 14, height: 14, borderRadius: 7,
        background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.3), 0 0 0 0.5px rgba(0,0,0,0.1)',
      }}/>
    </div>
  );
}

// Onboarding --------------------------------------------------------------
function OnboardingV_Welcome({ theme = 'dark' }) {
  return (
    <MacWindow theme={theme} toolbar={<span style={{fontSize: 12, color: 'var(--text-secondary)'}}>Welcome · 欢迎</span>}>
      <div style={{
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center',
        height: '100%', padding: 32, textAlign: 'center',
      }}>
        <div style={{
          width: 96, height: 96, borderRadius: 22,
          background: 'linear-gradient(155deg, #4A4A4F 0%, #6C6C70 50%, #D97757 100%)',
          boxShadow: '0 10px 30px rgba(0,0,0,0.3), inset 0 1px 0 rgba(255,255,255,0.18), inset 0 -1px 0 rgba(0,0,0,0.2)',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          marginBottom: 24,
        }}>
          <AppGlyph size={44} color="#fff"/>
        </div>
        <div style={{fontSize: 22, fontWeight: 700, letterSpacing: -0.4, lineHeight: 1.15}}>Welcome to cc-bar</div>
        <div style={{fontSize: 14, color: 'var(--text-secondary)', marginTop: 2}}>欢迎使用 cc-bar</div>
        <div style={{
          fontSize: 13, color: 'var(--text-secondary)',
          maxWidth: 360, marginTop: 14, lineHeight: 1.5,
        }}>
          Track Codex and Claude Code quota right from your menu bar. We'll detect your accounts automatically.
          <br/><span style={{fontSize: 12, opacity: 0.85}}>在菜单栏即时查看 Codex 与 Claude Code 的额度。我们将自动检测你的账号。</span>
        </div>
        <div style={{marginTop: 24, display: 'flex', flexDirection: 'column', gap: 8, alignItems: 'center'}}>
          <PrimaryButton theme={theme}>Get started · 开始</PrimaryButton>
          <button style={{
            border: 0, background: 'transparent',
            color: 'var(--accent)', fontFamily: 'inherit',
            fontSize: 12, padding: '6px 10px', cursor: 'pointer',
          }}>What's new in 1.0 · 新功能</button>
        </div>
        <div style={{position: 'absolute', bottom: 16, left: 0, right: 0, display: 'flex', justifyContent: 'center', gap: 6}}>
          {[true, false, false, false].map((on, i) => (
            <span key={i} style={{width: 6, height: 6, borderRadius: 3, background: on ? 'var(--accent)' : 'var(--fill)'}}/>
          ))}
        </div>
      </div>
    </MacWindow>
  );
}

function OnboardingV_DetectAccounts({ theme = 'dark' }) {
  return (
    <MacWindow theme={theme} toolbar={<span style={{fontSize: 12, color: 'var(--text-secondary)'}}>2 of 4 · Detect accounts · 检测账号</span>}>
      <div style={{padding: 28, height: '100%', display: 'flex', flexDirection: 'column'}}>
        <div style={{fontSize: 18, fontWeight: 700, letterSpacing: -0.3}}>We found these accounts</div>
        <div style={{fontSize: 12.5, color: 'var(--text-secondary)', marginTop: 4}}>检测到以下账号，请勾选要显示的服务</div>

        <div style={{marginTop: 18, display: 'flex', flexDirection: 'column', gap: 10}}>
          <DetectedAccount
            theme={theme} checked
            color="#6C6C70" glyph={<CodexGlyph size={16} color="#fff"/>}
            name="Codex" cn="OpenAI · GPT-5 · Plus"
            email="user@example.com"
            source="~/.codex/auth.json"
          />
          <DetectedAccount
            theme={theme} checked
            color="#D97757" glyph={<CCGlyph size={16} color="#fff"/>}
            name="Claude Code" cn="Anthropic · Max 20×"
            email="user@example.com"
            source="~/.claude/credentials.json"
          />
          <DetectedAccount
            theme={theme} muted
            color="#7E7E84" glyph={<CodexGlyph size={16} color="#fff"/>}
            name="Codex (Work)" cn="OpenAI · Pro"
            email="user@company.com"
            source="~/.codex/auth.work.json"
          />
        </div>

        <div style={{
          marginTop: 18, padding: '10px 14px', borderRadius: 10,
          background: theme === 'dark' ? 'rgba(10,132,255,0.12)' : 'rgba(0,122,255,0.08)',
          boxShadow: 'inset 0 0 0 0.5px ' + (theme === 'dark' ? 'rgba(10,132,255,0.3)' : 'rgba(0,122,255,0.2)'),
          display: 'flex', gap: 10, alignItems: 'flex-start',
          fontSize: 11.5, lineHeight: 1.45,
        }}>
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" style={{flexShrink: 0, marginTop: 2, color: 'var(--accent)'}}>
            <circle cx="8" cy="8" r="6" stroke="currentColor" strokeWidth="1.4"/>
            <path d="M8 4.5V8.5M8 11V11.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round"/>
          </svg>
          <div>
            <div style={{color: 'var(--text-primary)', fontWeight: 500}}>Read-only access · 仅读取</div>
            <div style={{color: 'var(--text-secondary)', marginTop: 2}}>cc-bar reads quota status locally. It never sends your credentials anywhere.<br/>cc-bar 仅本地读取额度，不会向任何地方发送你的凭据。</div>
          </div>
        </div>

        <div style={{marginTop: 'auto', display: 'flex', alignItems: 'center', gap: 8, paddingTop: 18}}>
          <SecondaryButton theme={theme}>Back · 上一步</SecondaryButton>
          <span style={{marginLeft: 'auto'}}/>
          <SecondaryButton theme={theme}>Add manually · 手动添加</SecondaryButton>
          <PrimaryButton theme={theme}>Continue · 继续</PrimaryButton>
        </div>
      </div>
    </MacWindow>
  );
}

function DetectedAccount({ theme, checked, muted, color, glyph, name, cn, email, source }) {
  const isDark = theme === 'dark';
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 13,
      padding: '14px 16px',
      borderRadius: 12,
      background: isDark ? 'rgba(60,60,63,0.4)' : '#fff',
      boxShadow: 'inset 0 0 0 0.5px ' + (isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.07)'),
      opacity: muted ? 0.6 : 1,
    }}>
      <CheckItem checked={checked}/>
      <span style={{width: 34, height: 34, borderRadius: 8, background: color, display: 'inline-flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0}}>{glyph}</span>
      <div style={{flex: 1, minWidth: 0}}>
        <div style={{fontSize: 13, fontWeight: 600}}>{name} <span style={{color: 'var(--text-tertiary)', fontWeight: 400, marginLeft: 4}}>· {cn}</span></div>
        <div style={{fontSize: 11.5, color: 'var(--text-secondary)', marginTop: 1}}>{email}</div>
        <div style={{fontSize: 10, color: 'var(--text-tertiary)', fontFamily: 'var(--font-mono)', marginTop: 2}}>{source}</div>
      </div>
    </div>
  );
}

function PrimaryButton({ theme, children, onClick }) {
  return (
    <button onClick={onClick} style={{
      height: 26, padding: '0 16px',
      borderRadius: 7, border: 0, cursor: 'pointer',
      background: 'var(--accent)',
      color: '#fff',
      fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500,
      boxShadow: '0 0.5px 0 rgba(0,0,0,0.15), 0 1px 3px rgba(0,122,255,0.25)',
    }}>{children}</button>
  );
}

function SecondaryButton({ theme, children, onClick }) {
  const isDark = theme === 'dark';
  return (
    <button onClick={onClick} style={{
      height: 26, padding: '0 12px',
      borderRadius: 7, border: 0, cursor: 'pointer',
      background: isDark ? 'rgba(120,120,128,0.36)' : '#fff',
      color: 'var(--text-primary)',
      fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500,
      boxShadow: isDark
        ? 'inset 0 0 0 0.5px rgba(255,255,255,0.08), 0 0.5px 1px rgba(0,0,0,0.2)'
        : 'inset 0 0 0 0.5px rgba(0,0,0,0.16), 0 0.5px 1.5px rgba(0,0,0,0.06)',
    }}>{children}</button>
  );
}

Object.assign(window, {
  PrefsV_Main, OnboardingV_Welcome, OnboardingV_DetectAccounts,
  PrefsGroup, PrefsRow, AccountRow, Toggle, DropdownPill, CheckboxGroup, CheckItem,
  RadioGroup, RadioItem, Slider, PrimaryButton, SecondaryButton, DetectedAccount,
});
