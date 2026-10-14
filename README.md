# satsolv

Bindingi [H#](https://) do [libsolv](https://github.com/openSUSE/libsolv) —
biblioteki SAT-solvera używanej m.in. przez `libzypp`/`zypper` (openSUSE),
`dnf`/`rpm`, `conda`/`rattler` i inne menedżery pakietów do rozwiązywania
zależności.

**100% H#.** Żadnego kodu C ani Rust napisanego przez nas — łączymy się
bezpośrednio z prawdziwymi, eksportowanymi symbolami `libsolv`/`libsolvext`
przez `extern static [c, "..."]`, zgodnie ze składnią FFI opisaną w README H#.

> **Status:** biblioteka nie została jeszcze skompilowana ani przetestowana
> wobec prawdziwego libsolv w tym środowisku (brak zbudowanego toolchaina
> H# + zainstalowanego libsolv-dev). Składnia jest ręcznie zweryfikowana
> wobec parsera/typecheckera H#, a sygnatury/stałe libsolv wobec jego
> nagłówków źródłowych — ale realna kompilacja + `bytes test` to konieczny
> następny krok przed użyciem produkcyjnym.

## Wymagania systemowe

**Tylko platformy 64-bitowe (LP64): x86_64, aarch64, riscv64.** `mod queue`
i `mod repo::set_priority/get_priority` czytają/piszą surową pamięć
prawdziwych struktur C libsolv pod stałymi offsetami wyliczonymi dla
64-bitowych wskaźników — na platformie 32-bitowej byłyby błędne. Biblioteka
weryfikuje to założenie w runtime (zobacz "Uwagi techniczne" niżej) i
**panikuje z czytelnym komunikatem**, zamiast po cichu psuć pamięć, jeśli
się nie zgadza — ale i tak nie próbuj używać tego na wasm32 czy platformie
32-bitowej.

`satsolv` **linkuje** się z libsolv — sama biblioteka nie jest w to
wliczona. Przed budową projektu korzystającego z `satsolv` zainstaluj
nagłówki/biblioteki dev libsolv (razem z rozszerzeniami — potrzebujemy
`libsolvext` dla parsera formatu "testtags"), np.:

```sh
# Debian/Ubuntu
sudo apt install libsolv-dev

# Fedora
sudo dnf install libsolv-devel

# openSUSE
sudo zypper install libsolv-devel

# Arch
sudo pacman -S libsolv
```

`extern static [c, "libsolv"]` / `extern static [c, "libsolvext"]` w kodzie
H# próbują najpierw `pkg-config --static --libs libsolv` (odpowiednio
`libsolvext`), a jeśli `pkg-config` nie znajdzie pliku `.pc`, spadają na
`-lsolv` / `-lsolvext`.

### Błąd `cannot find -lsolv` / "only a shared libsolv.so was found"

**Od teraz robi to `bit` sam:** `Bit.hk` ma `[build] native => bash scripts/bit-native.sh`.
Przed kompilacją (także gdy satsolv jest zależnością libhammer/hammer) skrypt sprawdza, czy
kompilator widzi `libsolv.a` + `libsolvext.a`; jeśli nie — buduje je (git + cmake + make + cc)
do `.bit/native/libsolv/lib`, a bit dopisuje ten katalog do `LIBRARY_PATH`. Wystarczy mieć
narzędzia (`sudo apt install git cmake build-essential pkg-config libexpat1-dev zlib1g-dev liblzma-dev`).
Ręczna procedura poniżej jest potrzebna tylko poza `bit`.

`satsolv` linkuje libsolv **statycznie** (`link => static`), a pakiety `-dev`
większości dystrybucji dają tylko `libsolv.so`. Zbuduj statyczne archiwa
(z `-fPIC`, bo `.hlib` jest linkowany jako biblioteka współdzielona) do
lokalnego prefiksu — jednorazowo:

```sh
# Debian/Ubuntu: nagłówki potrzebne do budowy
sudo apt install git cmake build-essential pkg-config libexpat1-dev zlib1g-dev liblzma-dev

scripts/install-static-libsolv.sh        # -> ~/.hackeros/native/libsolv/lib/libsolv{,ext}.a
source scripts/env.sh                    # PKG_CONFIG_PATH, LIBRARY_PATH, CPATH
bit
```

(`PREFIX=/opt/solv scripts/install-static-libsolv.sh` zmienia prefiks;
`SOLV_COMPRESSION=1` dodaje obsługę `.bz2`/`.zst`.)

**Kolejność linkowania:** w `src/ffi.h#` blok `libsolvext` stoi przed `libsolv`
— `libsolvext.a` używa symboli `libsolv.a`; w odwrotnej kolejności część
symboli zostaje nierozwiązana w `.hlib`.

**Programy końcowe** używające loaderów rpm-md/deb/arch (`repo::add_rpmmd_file`
itd.) muszą dolinkować zależności libsolvext, których `.hlib` nie wlicza
(`libexpat.a` z dystrybucji nie jest PIC, więc nie da się go wpiąć do `.hlib`):

```sh
export LDFLAGS="-lexpat -lz -llzma"
```

Programy, które nie wołają loaderów, tego nie potrzebują.

## Struktura plików

```
src/lib.h#          fasada: enum SatResult + `mod ...` (kolejność = kolejność łączenia)
src/ffi.h#          wszystkie `extern` (libc, libsolvext, libsolv) — kolejność ma znaczenie
src/result.h#       odczyt SatResult bez match
src/pool.h#         Pool, Id/stringi, wersje, flagi, rootdir
src/queue.h#        Queue w czystym H#
src/repo.h#         Repo, loadery, zapis .solv
src/select.h#       selekcje (nazwy/glob)
src/job.h#          zadania solvera
src/solver.h#       Solver
src/transaction.h#  kroki transakcji, Plan, resolve_install
scripts/            install-static-libsolv.sh, env.sh, check-symbols.py
```

Przed zmianami w nazwach funkcji uruchom `scripts/check-symbols.py` (opcje
`--ver`, `--archives` w nagłówku skryptu) — wyłapuje kolizje z symbolami
libsolv, które psuły kompilację w 0.1.0.

## Instalacja

```sh
bytes add satsolv
```

## Szybki start

```h#
use "satsolv" from "sv"

fn main() is
    let p: int = sv::pool::new()
    sv::pool::set_arch(p, "x86_64")

    ;; repo "systemowe" (nic zainstalowanego na start)
    let system: int = sv::repo::new(p, "system")
    sv::pool::set_installed_repo(p, system)
    sv::repo::finalize(system)

    ;; repo "dostępne" — dwa pakiety zbudowane "z palca"
    let available: int = sv::repo::new(p, "available")
    sv::repo::set_priority(available, 10, 0)

    let foo: sv::repo::Pkg = sv::repo::new_pkg("foo", "1.0", "1", "x86_64")
    let mut bar: sv::repo::Pkg = sv::repo::new_pkg("bar", "2.0", "1", "x86_64")
    bar.requires = ["foo >= 1.0"]

    let res8 = sv::repo::add_packages(p, available, [foo, bar])
    if !sv::result::is_ok(res8) is
        let msg: string = sv::result::error_message(res8)
        write("Blad wczytywania pakietow: " + msg)
        return
    end
    sv::repo::finalize(available)

    sv::pool::create_whatprovides(p)

    ;; job: zainstaluj "bar" w wersji >= 1.5 (a solver dociągnie "foo")
    let jobs: int = sv::queue::new()
    let res9 = sv::job::install_name_version(jobs, p, "bar", ">=", "1.5")
    if !sv::result::is_ok(res9) is
        let msg: string = sv::result::error_message(res9)
        write("Blad joba: " + msg)
        return
    end

    let s: int = sv::solver::new(p)
    sv::solver::allow_downgrade(s, false)

    let problems: i32 = sv::solver::run(s, jobs)

    if problems > 0 is
        for msg in sv::solver::all_problems_as_strings(s) is
            write(msg)
        end
    else is
        let t: int = sv::transaction::create_from_solver(s)
        for sid in sv::transaction::installed_result(t) is
            write(sv::pool::solvable_to_str(p, sid))
        end
        sv::transaction::destroy(t)
    end

    sv::queue::destroy(jobs)
    sv::solver::destroy(s)
    sv::repo::destroy(available, false)
    sv::repo::destroy(system, false)
    sv::pool::destroy(p)
end
```

## Zmiana nazw w 0.2.0 (migracja z 0.1.0)

Funkcje-wrappery w `mod X` są w kompilatorze H# mangle'owane do `X_nazwa`,
więc `pool::create` stawało się `pool_create` — **dokładnie tym samym
symbolem co C-owy `pool_create` z libsolv** (`extern`). Skutek: wrapper
wołał sam siebie (nieskończona rekurencja) albo kompilacja kończyła się
błędem `Incorrect number of arguments passed to called function!`.
Wszystkie 26 kolidujących nazw zmieniono:

| było | jest |
|---|---|
| `pool::create` / `free` | `pool::new` / `destroy` |
| `pool::set_installed` | `pool::set_installed_repo` |
| `pool::createwhatprovides` | `pool::create_whatprovides` |
| `pool::str2id` / `id2str` / `dep2str` / `rel2id` | `pool::str_to_id` / `id_to_str` / `dep_to_str` / `rel_to_id` |
| `pool::evrcmp` / `evrcmp_str` | `pool::evr_compare` / `evr_compare_str` |
| `pool::errstr` | `pool::error_string` |
| `queue::free` | `queue::destroy` |
| `repo::create` / `free` / `internalize` | `repo::new` / `destroy` / `finalize` |
| `solver::create` / `free` | `solver::new` / `destroy` |
| `solver::set_flag` / `get_flag` | `solver::set_flag_value` / `get_flag_value` |
| `solver::solve` | `solver::run` |
| `solver::problem_count` / `next_problem` / `solution_count` | `solver::count_problems` / `next_problem_id` / `count_solutions` |
| `transaction::free` | `transaction::destroy` |
| `transaction::classify` / `classify_pkgs` | `transaction::classify_steps` / `classify_step_pkgs` |

Stałe `INSTALL`/`ERASE` istniały w dwóch modułach (stałe są w H# globalne po
spłaszczeniu modułów) — teraz `JOB_INSTALL`/`JOB_ERASE` oraz
`TRANS_INSTALL`/`TRANS_ERASE`. **Stałych używaj jako gołych nazw**
(`REL_EQ`, `DISTTYPE_DEB`, `JOB_INSTALL`), nie jako `pool::REL_EQ` — ścieżka
w pozycji wartości jest w AOT kompilowana do `0`.

Wzorce `match` w stylu `lib::SatResult::Ok(x)` nie parsują się w H#
(wzorzec ma najwyżej dwa segmenty) — używaj `result::is_ok` /
`result::error_message`.

## Struktura API

| moduł | co robi |
|---|---|
| `result` | odczyt `SatResult<i32>` bez `match`: `is_ok`, `value`, `error_message` |
| `pool` | cykl życia `Pool` (`new`/`destroy`), internowanie Id (`str_to_id`/`id_to_str`), porównania wersji (`evr_compare`/`evr_compare_str`), typ dystrybucji (`set_disttype`), flagi (`set_option`/`get_option`), rootdir (`set_root_dir`) |
| `repo` | cykl życia `Repo` (`new`/`destroy`/`clear`/`finalize`), priorytety, wczytywanie: `.solv` (`add_solv_file`), rpm-md (`add_rpmmd_file`), Debian `Packages` (`add_deb_packages_file`), Arch `.db` (`add_arch_repo_file`), "z palca" (`add_packages`), zapis `.solv` (`write_solv_file`) |
| `queue` | odpowiednik `Queue` z libsolv (kolejka `Id`), własna implementacja w H# |
| `select` | selekcje libsolv: `find(p, "lib*", SELECTION_NAME \| SELECTION_GLOB)` |
| `job` | stałe `SOLVER_*` + budowanie zadań (`install_name`, `install_name_version`, `install_glob`/`erase_glob`/`update_glob`, `verify_all`, ...) |
| `solver` | cykl życia `Solver` (`new`/`destroy`), flagi, `run()`, odczyt problemów |
| `transaction` | wynik `run()`: `classify_steps`, `classify_step_pkgs`, `installed_result`, `type_name`, oraz gotowy `resolve_install(p, ["bar"])` → `Plan { ok, problems, steps }` |

Funkcje, które mogą faktycznie zawieść (I/O na plikach, parsowanie repo,
zły operator porównania wersji), zwracają `SatResult<T>`
(`SatResult::Ok(wartosc)` / `SatResult::Err(opis_bledu)`) zamiast surowego
kodu powrotu — sprawdź wynik przez `match`, tak jak w przykładach wyżej.

## Budowanie pakietów bez pliku `.solv`

Do syntetycznego tworzenia pakietów `satsolv` **nie** grzebie w wewnętrznym
layoucie struktury `Solvable` (to zbyt kruche i zależne od wersji libsolv).
Zamiast tego używa oficjalnego, udokumentowanego formatu tekstowego libsolv
o nazwie *testtags* przez prawdziwą funkcję `testcase_add_testtags`
(`libsolvext`):

```h#
let mut pkg: sv::repo::Pkg = sv::repo::new_pkg("nginx", "1.24.0", "2", "x86_64")
pkg.requires   = ["libc.so.6()(64bit)", "openssl >= 3.0"]
pkg.provides   = ["webserver"]
pkg.conflicts  = ["apache2"]

let res10 = sv::repo::add_packages(p, myrepo, [pkg])
if !sv::result::is_ok(res10) is
    let msg: string = sv::result::error_message(res10)
    write("blad: " + msg)
end
```

**Walidacja wejścia.** Format *testtags* jest rozdzielany liniami (linia
`"#>=Tag: wartość"` trwa do końca linii), więc `add_packages` waliduje
każde pole *przed* sklejeniem tekstu:

- `name`/`version`/`release`/`arch` muszą być pojedynczym tokenem — bez
  spacji, tabulatorów ani znaków nowej linii (są rozdzielone spacją w
  jednej linii `#>=Pkg: name version release arch`, więc spacja w
  środku przesunęłaby kolejne pola).
- Wpisy w `requires`/`provides`/`conflicts`/`obsoletes`/`recommends`/
  `suggests` mogą zawierać spacje (np. `"foo >= 1.0"`), ale nie mogą
  zawierać `\n`/`\r` — to jedyny sposób, żeby wartość „uciekła” poza swój
  tag i stała się osobną, dowolną linią `#>=...` (czyli wstrzyknęła
  dodatkowy, niechciany pakiet do repo).

Jeśli którekolwiek pole nie przejdzie walidacji, `add_packages` zwraca
`SatResult::Err(...)` z opisem problemu i **nic nie zapisuje** — ani jeden
pakiet z podanej listy nie trafia do repo.

## Uwagi techniczne (dla ciekawych/kontrybutorów)

* Wszystkie nieprzezroczyste wskaźniki C (`Pool*`, `Repo*`, `Solver*`,
  `Transaction*`, `Queue*`, `FILE*`) są reprezentowane jako H# `int`
  (64-bitowy adres) — tak samo jak `malloc`/`free` w przykładzie z README H#.
  Nie wykonuj na nich arytmetyki poza tym modułem.
* `Id` w libsolv to `typedef int Id` (C `int`, 32 bity ze znakiem) — dlatego
  wiążemy go jako H# `i32`, nie `int` (który w H# to 64-bitowy `int64_t`).
  Użycie `int` tutaj dałoby błędne wartości dla ujemnych Id/kodów błędów.
* `queue_push`/`queue_pop`/`queue_shift` z `queue.h` libsolv są
  `static inline` — **nie mają eksportowanego symbolu** w `.so`/`.a`, więc
  nie da się ich zbindować przez `extern`. Moduł `queue` odtwarza ich
  logikę w czystym H#, operując na surowej pamięci struktury `Queue`
  (layout `elements`/`count`/`alloc`/`left`, 32 bajty — niezmienny od lat
  w publicznym ABI libsolv) przez wbudowane `ptr_read_i32`/`ptr_write_i32`/
  `ptr_read_ptr`/`arc_alloc` w blokach `unsafe`. Sam rozrost bufora
  (`queue_alloc_one`) **jest** prawdziwym, zlinkowanym kodem libsolv.
* **Założenie LP64 i samotest.** Powyższy layout `Queue` (i analogiczny
  layout pól `priority`/`subpriority` w `mod repo`) zakłada 64-bitowe
  wskaźniki — prawdziwe dla x86_64/aarch64/riscv64, jedynych sensownych
  natywnych celów kompilatora H# do linkowania z libsolv (H# potrafi też
  kompilować na wasm32, gdzie wskaźniki są 32-bitowe i te offsety byłyby
  błędne — ale wasm32 i tak nie linkuje natywnych `.so`, więc to nie jest
  realny scenariusz). `queue::new()` **weryfikuje to w runtime**:
  `queue_init()` to prawdziwy, skompilowany kod libsolv, który na LP64
  zapisuje zera pod dokładnie znanymi nam offsetami — jeśli po jego
  wywołaniu odczytamy pod tymi offsetami coś innego niż zera, layout się
  nie zgadza i biblioteka **panikuje** z czytelnym komunikatem zamiast po
  cichu kontynuować z uszkodzoną pamięcią. To nie jest dowód matematyczny
  (teoretycznie "obcy" bajt mógłby przypadkiem wylądować jako zero), ale w
  praktyce bardzo skuteczna siatka bezpieczeństwa.
* Świadomie nie dotykamy wewnętrznego layoutu `Pool`/`Solvable` — zbyt
  złożone i zbyt kruche na zmiany między wersjami. Stąd wybór
  `testcase_add_testtags` do tworzenia pakietów programistycznie i
  `repo_add_solv` do wczytywania prawdziwych metadanych repo. `Repo`
  (dla `priority`/`subpriority`) i `Queue` to jedyne dwie struktury C,
  których pola czytamy/piszemy bezpośrednio — obie mają w pełni publiczny,
  udokumentowany prefiks pól (poza `#ifdef LIBSOLV_INTERNAL`), więc jest
  to świadomy, ograniczony wyjątek od reguły "nie dotykamy layoutu".
* **`transaction::classify_steps` nie zwraca listy Id pakietów.** Zwraca
  kolejkę wypełnioną czwórkami `(type_id, count, from_id, to_id)` — po
  jednej czwórce na każdą *klasę* kroków transakcji (potwierdzone wobec
  SWIG-owych bindingów libsolv, `bindings/solv.i`). `mod transaction`
  dekoduje to poprawnie na `[TransactionClass]`; żeby dostać faktyczne Id
  pakietów jednej klasy, użyj `classify_pkgs()` z wynikiem `classify()`.

## Licencja

MIT (bindingi). libsolv samo w sobie jest na licencji BSD — patrz jego
własne repozytorium.
