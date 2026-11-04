#include <solv/pool.h>

const char *satsolv_solvid2str(Pool *pool, Id p) {
    if (!pool || p <= 0 || p >= pool->nsolvables) return "";
    return pool_solvid2str(pool, p);
}

/* Strukturalne akcesory solvable'a po Id (nazwa / evr / arch) — bez parsowania etykiety "name-evr.arch",
 * ktora dla Debiana (myslniki w wersji, epoch ":") jest niejednoznaczna. */
static Solvable *sv_get(Pool *pool, Id p) {
    if (!pool || p <= 0 || p >= pool->nsolvables) return 0;
    return pool->solvables + p;
}
const char *satsolv_solvid_name(Pool *pool, Id p) {
    Solvable *s = sv_get(pool, p);
    return s ? pool_id2str(pool, s->name) : "";
}
const char *satsolv_solvid_evr(Pool *pool, Id p) {
    Solvable *s = sv_get(pool, p);
    return s ? pool_id2str(pool, s->evr) : "";
}
const char *satsolv_solvid_arch(Pool *pool, Id p) {
    Solvable *s = sv_get(pool, p);
    return s ? pool_id2str(pool, s->arch) : "";
}
