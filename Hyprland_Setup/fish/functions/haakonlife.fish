function haakonlife --description 'Show Haakon Life play time for everyone on the live world'
    curl -s 'https://haakonlife-d4ef2-default-rtdb.firebaseio.com/playtime/live.json' | node -e '
let d=JSON.parse(require("fs").readFileSync(0,"utf8"))||{};
const r=Object.values(d).sort((a,b)=>b.s-a.s);
const f=s=>`${Math.floor(s/3600)}h ${String(Math.floor(s/60)%60).padStart(2,"0")}m`;
for(const p of r)console.log(String(p.name).padEnd(16),f(p.s).padStart(8)," last",new Date(p.t).toLocaleString());
console.log("TOTAL".padEnd(16),f(r.reduce((a,p)=>a+p.s,0)).padStart(8),"("+r.length+" names)");'
end
