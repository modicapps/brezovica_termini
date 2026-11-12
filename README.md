# Odbojka Brezovica (družinska različica): GitHub Pages + Supabase

Družinski urnik treningov in tekem (Lado, Tina, Val, Tim) brez Google Preglednice in Apps Script.

```
Telefon / računalnik  →  GitHub Pages (statična stran: docs/)  →  Supabase (PostgreSQL + funkcije api_*)
```

- **GitHub Pages** gosti samo stran (`docs/index.html`). V njej ni podatkov in ni skrivnosti.
- **Supabase** hrani podatke. Tabele so v shemi `app`, ki je zunaj API-ja. Stran kliče samo funkcije `api_*`.
- Gesel ni. Odpreš stran, izbereš »kdo si« (starš ali otrok). **Neobvezna družinska koda** zaščiti javni naslov (glej 4. korak).

> **Pomembno:** SQL (`supabase/schema.sql`) je pisan skrbno, a ga nisem mogel zagnati na pravem Supabase projektu. Stran sem preizkusil z lažnim strežnikom, imena in parametri vseh 26 funkcij `api_*` v strani in SQL-u se ujemajo. Pri prvem zagonu sledi preizkusu v 5. koraku. Če Supabase ob »Run« javi napako, pošlji sporočilo in jo popravim.

## Kaj je v paketu

| Pot | Namen |
|---|---|
| `supabase/schema.sql` | Tabele, redni urnik, člani, igralca, Timove odsotnosti, vse funkcije `api_*`. Zaženeš enkrat v Supabase. |
| `docs/index.html` | Aplikacija (ista kot v Apps Script v22, klici prestavljeni na Supabase). |
| `docs/config.js` | Povezava s Supabase (URL in »anon« ključ). Vpišeš svoja podatka. |
| `.github/workflows/pages.yml` | Samodejna objava na GitHub Pages ob vsakem potisku. |
| `tools/build-docs.ps1` | Iz `..\apps-script\Index.html` znova naredi `docs/index.html`. |

## 1. Supabase (približno 10 minut)

1. Odpri [supabase.com](https://supabase.com), ustvari račun in **New project**. Regija: **EU (Frankfurt)** (podatki mladoletnikov). Shrani geslo za bazo.
2. Počakaj, da je projekt pripravljen.
3. Levo **SQL Editor > New query**. Odpri `supabase/schema.sql`, prekopiraj **celotno vsebino**, prilepi in pritisni **Run**. Spodaj mora pisati »Success«. Datoteko lahko poženeš večkrat, podatkov ne prepiše.
4. **Project Settings > API**: prepiši **Project URL** in **anon public** ključ. Ključa **service_role** nikoli ne uporabi in ga ne vpisuj nikamor.

## 2. Povezava (1 minuta)

V `docs/config.js` vpiši:

```js
window.APP_CONFIG = {
  url: 'https://abcdefgh.supabase.co',
  anonKey: 'eyJ...'
};
```

Ključ »anon« sme biti v javnem repozitoriju: tabele so zunaj API-ja, funkcije pa preverjajo žeton in kodo.

## 3. GitHub in GitHub Pages (približno 10 minut)

1. Na [github.com](https://github.com) ustvari račun in **New repository** (npr. `odbojka-brezovica`). Izberi **Public** (brezplačne Pages delujejo samo pri javnih repozitorijih). V njem ni skrivnosti; imena članov so v bazi, ne v repozitoriju.
2. **Add file > Upload files** in povleci **celotno vsebino te mape**, vključno s skrito mapo `.github` (v Raziskovalcu vklopi »Skrite datoteke«). Lažje: program **GitHub Desktop**. Pritisni **Commit changes**.
3. **Settings > Pages > Build and deployment > Source: GitHub Actions**.
4. Zavihek **Actions**: delovni tok »Objava na GitHub Pages« se zažene ob potisku (sicer »Run workflow«). Ko je zelen, je stran na  
   `https://TVOJE-UPORABNISKO-IME.github.io/odbojka-brezovica/`

## 4. Družinska koda (priporočeno)

Naslov na GitHub Pages je javen in ga je lažje uganiti kot naključen naslov Apps Script. Brez kode lahko vsak, ki naslov najde, vidi urnik in izbere »kdo si«.

1. Odpri stran, izberi **Lado** (starš).
2. **Nastavitve > Družina in zaščita**: vpiši kodo (vsaj 6 znakov), **Shrani kodo**.
3. Na vsakem telefonu enkrat vpišeš kodo, nato se zapomni. Kodo odstraniš s praznim poljem. Po 20 napačnih poskusih je vstop 15 minut zaklenjen.

## 5. Preizkus (ko prvič deluje)

1. Odpri stran. Prikaže se urnik in »Kdo si?«. Izberi Lado: vidiš vse tri ekipe in lahko vse urejaš.
2. Izberi Val (otrok): vidi samo Mladince in svoje igralce. Preizkusi odpoved treninga, dodajanje tekme, vpis prisotnosti (po začetku treninga) in odsotnost.
3. Starš v **Nastavitve** preveri redne termine, dnevnik sprememb in kodo.
4. Pri napaki odpri F12 > Network in poglej odgovor klica `api_…`. Besedilo napake je razumljivo. Če se stran sploh ne naloži, preveri `config.js`.

## 6. Člani, igralci, podatki

- **Člani** (Lado, Tina, Val, Tim): Supabase **Table Editor** > shema `app` > `members`. Polja: `role` (`starš` ali `otrok`), `teams` (npr. `{Mladinci}`), `pids` (ID igralcev). Starš ima vse ekipe.
- **Igralci** se urejajo v aplikaciji (Nastavitve).
- Termini, tekme in odsotnosti iz Preglednice: najlažje ponovno vneseš v aplikaciji. Začetni redni urnik in Timove odsotnosti so že v `schema.sql`.

## 7. Posodobitve

- **Aplikacija:** uredi `..\apps-script\Index.html`, poženi `tools\build-docs.ps1`, naloži spremenjen `docs/index.html` na GitHub (objava je samodejna). Ponovno vpiši URL in ključ le, če boš prepisal `config.js`.
- **Baza:** `schema.sql` lahko vedno znova poženeš. Funkcije se posodobijo, podatki ostanejo.

## 8. Varnost in zasebnost

- V repozitoriju so samo koda in URL projekta Supabase.
- Dostop do podatkov je samo prek funkcij `api_*`; pisanje zahteva žeton (6 ur) in pravice: starš vse, otrok odpovedi, tekme in prisotnost svojih ekip/igralcev.
- Družinska koda je v bazi zgoščena (bcrypt). Izbira »kdo si« ni prijava z geslom: kdor pozna kodo, lahko izbere kogarkoli. Za družinski urnik je to običajno dovolj.
- Imena in prisotnost mladoletnikov so osebni podatki: razmisli o privolitvi, izbiraj kodo, ki je ne deliš javno, in vklopi dvostopenjsko prijavo v Supabase.
- Brezplačni Supabase po približno **tednu brez uporabe projekt začasno ustavi** (v nadzorni plošči ga z enim klikom zaženeš). Samodejnih varnostnih kopij ni: občasno Table Editor > Export.

## 9. Razlike od različice z Google Preglednico

- Podatkov ni mogoče urejati v Preglednici (Table Editor ali aplikacija).
- Stran se najprej naloži, nato pridejo podatki (približno 200–500 ms).
- Zaščite po Google računu ni; namesto nje družinska koda.
