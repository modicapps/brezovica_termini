# Iz apps-script\Index.html naredi statično stran docs\index.html (GitHub Pages + Supabase), družinska različica.
# Poženi iz mape github-supabase:  powershell -ExecutionPolicy Bypass -File tools\build-docs.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$src  = Join-Path $root '..\apps-script\Index.html'
$dst  = Join-Path $root 'docs\index.html'
if (-not (Test-Path $src)) { throw "Ne najdem $src" }
$h = [System.IO.File]::ReadAllText((Resolve-Path $src), [System.Text.Encoding]::UTF8)
$h = $h.Replace("`r`n", "`n")

function Swap([string]$what, [string]$from, [string]$to) {
  if (-not $script:h.Contains($from)) { throw "Ni najdeno za zamenjavo: $what" }
  $script:h = $script:h.Replace($from, $to)
}

# 1) Podatki se naložijo z API-ja, ne vdelani v stran.
Swap 'INIT' 'const INIT=<?!= initJson ?>;' 'const INIT=null;'
Swap 'base' '<base target="_top">' ''

# 2) Klici strežnika: google.script.run -> Supabase (PostgREST rpc). Ime funkcije: setCancelMatch -> api_set_cancel_match.
$oldCall = "const call=(name,...a)=>new Promise((ok,no)=>google.script.run.withSuccessHandler(ok).withFailureHandler(no)[name](...a));"
$newCall = @'
const SIG={enter:['id','code'],logout:['token'],getData:['code'],getPrivate:['token'],setCancelTraining:['token','week','team','day','origFrom','cancel','note'],addMatch:['token','m'],updateMatch:['token','row','m'],deleteMatch:['token','row'],setCancelMatch:['token','row','cancel'],editTrainingWeek:['token','week','team','day','origFrom','m'],resetTrainingWeek:['token','week','team','day','origFrom'],addExtraTraining:['token','m'],changeSlot:['token','row','m'],endSlot:['token','row','date'],addSlot:['token','m'],savePlayer:['token','p'],deletePlayer:['token','id'],saveAttendance:['token','date','team','from','entries'],addAbsences:['token','m'],updateAbsence:['token','row','m'],deleteAbsence:['token','row'],addIndividual:['token','m'],updateIndividual:['token','row','m'],deleteIndividual:['token','row'],getLog:['token'],setFamilyCode:['token','code']};
function famCode(){try{const v=localStorage.getItem('fam_code');if(v)return v}catch(e){}return window.__famCode||''}
async function call(name,...a){const cfg=window.APP_CONFIG||{},keys=SIG[name];if(!keys)throw new Error('Neznana funkcija: '+name);
 if(!cfg.url||/TVOJ/.test(cfg.url))throw new Error('Manjka nastavitev Supabase v config.js.');
 if(name==='getData'&&a[0]===undefined)a[0]=famCode();
 if(name==='enter'&&a[1]===undefined)a[1]=famCode();
 const body={};keys.forEach((k,i)=>{body['p_'+k.replace(/[A-Z]/g,c=>'_'+c.toLowerCase())]=a[i]===undefined?null:a[i]});
 let r;try{r=await fetch(cfg.url+'/rest/v1/rpc/api_'+name.replace(/[A-Z]/g,c=>'_'+c.toLowerCase()),{method:'POST',headers:{'Content-Type':'application/json',apikey:cfg.anonKey,Authorization:'Bearer '+cfg.anonKey},body:JSON.stringify(body)})}catch(e){throw new Error('Ni povezave s strežnikom.')}
 const txt=await r.text();let j=null;try{j=txt?JSON.parse(txt):null}catch(e){}
 if(!r.ok)throw new Error((j&&(j.message||j.hint))||('Napaka '+r.status));
 if(j&&typeof j==='object'&&!Array.isArray(j)&&j.error)throw new Error(j.error);
 return j}
'@
Swap 'call' $oldCall $newCall

# 3) Nastavitve povezave (config.js) in oznaka različice.
Swap 'config' "<script>`nconst INIT" "<script src=`"config.js`"></script>`n<script>`nconst INIT"
$h = [regex]::Replace($h, "const VERSION='[^']*';", "const VERSION='S1 · Supabase';")
$h = $h.Replace('<meta charset="utf-8">', '<meta charset="utf-8"><meta name="theme-color" content="#174f93">')

# 4) Družinska koda: pogovorno okno, osvežitev podatkov z zaklepom, nastavitev kode.
$dlg = '<dialog id="dCode"><div class="dlg"><h2>Družinska koda</h2><div class="sub">Vpiši kodo, ki jo poznajo samo člani družine. Zapomni se v tem telefonu.</div><input id="codeIn" type="password" autocomplete="off" style="width:100%;margin-top:10px;padding:11px;border:1px solid #d7e0ed;border-radius:12px;font:inherit"><div class="row" style="margin-top:12px"><button class="btn primary" id="codeOk">Naprej</button></div><div class="err" id="eCode"></div></div></dialog>'
Swap 'dialog' '<dialog id="dMe">' ($dlg + "`n" + '<dialog id="dMe">')

Swap 'refresh' "async function refresh(){try{parse(await call('getData'));render()}" @'
function askCode(m){$('eCode').textContent=m||'';$('codeIn').value='';if(!$('dCode').open)$('dCode').showModal()}
async function refresh(){try{const d=await call('getData');if(d&&d.locked){askCode(d.napaka||'');return}parse(d);render()}
'@
Swap 'codeok' "async function toggleSec(){" @'
$('codeOk').onclick=async()=>{const v=$('codeIn').value.trim();if(!v)return;window.__famCode=v;try{localStorage.setItem('fam_code',v)}catch(e){}$('dCode').close();await refresh();startFamily()};
$('codeIn').addEventListener('keydown',e=>{if(e.key==='Enter')$('codeOk').click()});
$('dCode').addEventListener('cancel',e=>e.preventDefault());
async function toggleSec(){
'@
# toggleSec: telo funkcije
$oldTog = "async function toggleSec(){`n`$('eSec').textContent='';try{await call('setSecurity',token,!zascita);await refresh();renderSettings()}catch(e){fail('eSec',e)}}"
$oldTog2 = "`$('eSec').textContent='';try{await call('setSecurity',token,!zascita);await refresh();renderSettings()}catch(e){fail('eSec',e)}}"
$newTog2 = "`$('eSec').textContent='';const v=(`$('famCode').value||'').trim();try{await call('setFamilyCode',token,v);window.__famCode=v;try{v?localStorage.setItem('fam_code',v):localStorage.removeItem('fam_code')}catch(e){}await refresh();renderSettings();`$('eSec').textContent=v?'Koda shranjena.':'Koda odstranjena.'}catch(e){fail('eSec',e)}}"
Swap 'toggleSec' $oldTog2 $newTog2
$h = $h.Replace("async function toggleSec(){`n`$('eSec')", "async function toggleSec(){`$('eSec')")

# 5) Družinske nastavitve: koda namesto Google zaščite.
$oldSec = '<div style="margin-top:12px"><button class="btn small" id="secBtn">Zaščita po Google računu: ${zascita?' + "'vklopljena (izklopi)':'izklopljena (vklopi)'" + '}</button><div class="hint" style="margin-top:6px">Ko je vklopljena, aplikacija člana prepozna po Google računu in izbire »kdo si« ni. Potrebna je drugačna objava aplikacije (glej navodila).</div><div class="err" id="eSec"></div></div>'
$newSec = '<div style="margin-top:12px"><div class="hint">Družinska koda: ker je stran javna, jo lahko zaščitiš s kodo (vsaj 6 znakov), ki jo poznajo samo člani družine. Prazno polje in »Shrani kodo« kodo odstrani.</div><div class="row" style="margin-top:8px"><input id="famCode" type="text" autocomplete="off" placeholder="nova družinska koda" style="flex:1;min-width:160px;padding:11px;border:1px solid #d7e0ed;border-radius:12px;font:inherit"><button class="btn small" id="secBtn">Shrani kodo</button></div><div class="err" id="eSec"></div></div>'
Swap 'secBtn' $oldSec $newSec
Swap 'clani-hint' 'Člane, ekipe in e-pošte urejaš v listu »Člani«.' 'Člane in ekipe urejaš v Supabase: Table Editor > shema app > tabela members.'

# 6) Besedila, ki so veljala za Apps Script / Preglednico.
Swap 'verzija' ' ⚠ različici se ne ujemata: prepiši obe datoteki v Apps Script in naredi nov Deploy.' ' ⚠ različici se ne ujemata: osveži stran (Ctrl+F5) ali preveri, ali je SQL v Supabase posodobljen.'
Swap 'noga' 'Urnik se bere iz skupne Google Preglednice.' 'Urnik se bere iz skupne baze.'
$dir = Split-Path -Parent $dst
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
[System.IO.File]::WriteAllText($dst, $h, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Ustvarjeno: $dst"
