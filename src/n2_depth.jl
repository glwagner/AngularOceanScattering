using JLD2, Printf
f=jldopen(expanduser("~/AngularOceanScattering-data/runs/production-4m2m/profiles.jld2"))
it=sort(parse.(Int,keys(f["timeseries/t"]))); ts=[f["timeseries/t/$i"] for i in it]
g(v,i)=vec(f["timeseries/$v/$i"])
T0=g("T",it[1]); println("lengths T,wT,W,κ: ",length.(g.(["T","wT","W","κₑ"],it[end])))
z=collect(-159:2:-1.0); hs=[12,24,36,48]; at(h)=it[argmin(abs.(ts.-h*3600))]
println("layer N² % of initial at ",hs," h")
for zt in -50:-10:-150
 ku=findfirst(>(zt-1),z)+0; kl=ku-5; kl<1 && continue; @printf("%5d..%5d",zt,zt-10)
 for h in hs; T=g("T",at(h)); @printf(" %7.1f",100*(T[ku]-T[kl])/(T0[ku]-T0[kl])); end; println()
end
println("z, T-T0, κₑ, sgs flux -κ dT/dz, wT, W*T  (48 h window mean over last 6 h)")
idx=it[findall(>=(42*3600),ts)]; m(v)=sum(g(v,i) for i in idx)/length(idx)
T=m("T");κ=m("κₑ");wT=m("wT");W=m("W")
for k in 11:5:71
 kk=length(κ)==80 ? (κ[k]+κ[k+1])/2 : κ[k+1]; dT=(T[k+1]-T[k])/2
 wf=length(wT)==80 ? (wT[k]+wT[k+1])/2 : wT[k+1]; wb=length(W)==80 ? (W[k]+W[k+1])/2 : W[k+1]
 @printf("%6.0f %10.5f %9.2e %10.2e %10.2e %10.2e\n",z[k]+1,T[k]-T0[k],kk,-kk*dT,wf,wb*(T[k]+T[k+1])/2)
end
