"""Compile selected pure Lab EA functions against a small C++ MT5 shim.

Run with: python3 tests/test_squeeze_lab.py
This is not a substitute for compiling in MetaEditor or MT5 broker tests.
"""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parent.parent / 'SqueezeMomentum_LB_EA_Lab.mq5').read_text()

def section(start, end):
    return source[source.index(start):source.index(end, source.index(start))]

blocks = [
    section('int SignalFromTransition(', '// BB/KC'),
    section('double LabATR(', 'int LoadRates('),
    section('int EvaluatePositionExit(', 'bool ManageSignalExits('),
    section('bool BuildFixedExits(', 'void DrawSignalArrow('),
    section('bool LabRiskBudgetOK(', '// Equity estimate'),
]
code = '\n'.join(blocks)
for old, new in (
    ('const MqlRates &rates[]', 'const vector<MqlRates> &rates'),
    ('const double &values[]', 'const vector<double> &values'),
    ('const ENUM_SQZ_BAR_COLOR &colors[]', 'const vector<ENUM_SQZ_BAR_COLOR> &colors'),
    ('const bool &valid[]', 'const vector<int> &valid'),
):
    code = code.replace(old, new)

pre = r'''
#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>
using namespace std;
using datetime=long long;
#define MathMax max
#define MathMin min
#define MathAbs fabs
#define MathSqrt sqrt
#define _Point 0.01
#define _Symbol string("TEST")
#define _Digits 2
enum ENUM_SQZ_BAR_COLOR {SQZ_COLOR_NONE, SQZ_COLOR_LIME, SQZ_COLOR_GREEN, SQZ_COLOR_RED, SQZ_COLOR_MAROON};
enum ENUM_SQZ_STATE {SQZ_STATE_UNKNOWN, SQZ_STATE_ON, SQZ_STATE_OFF, SQZ_STATE_NONE};
enum ENUM_LAB_ENTRY_MODE {LAB_CLASSIC,LAB_SQUEEZE_REVERSAL,LAB_SQUEEZE_TREND};
enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL };
enum { POSITION_TYPE_BUY=20, POSITION_TYPE_SELL, POSITION_TYPE, POSITION_PRICE_OPEN, POSITION_TIME, POSITION_SL, POSITION_VOLUME, POSITION_SYMBOL, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, ACCOUNT_EQUITY };
struct MqlRates {double high,low,close; datetime time; int state;};
struct MqlTick {double bid,ask;};
template<class T> int ArraySize(const vector<T>& v){return (int)v.size();}
bool InpWeightedSignals=false;
int InpLabATRPeriod=2,InpSqueezeLookback=3,InpKCLength=2,InpTakeProfitSignalCount=2,InpStopLossSignalCount=2,InpFixedTakeProfitPoints=0,InpFixedStopLossPoints=0;
double InpWeightReference=0.1,InpWeightMinimum=0.25,InpWeightMaximum=2,InpRiskBudgetPercent=0;
ENUM_LAB_ENTRY_MODE InpLabEntryMode=LAB_CLASSIC;
ENUM_SQZ_STATE ComputeSqueezeState(const vector<MqlRates>& r,int i){return (ENUM_SQZ_STATE)r[i].state;}
struct Pos {bool open=true; int side=POSITION_TYPE_BUY; double entry=100,sl=99,vol=1; datetime time=2;} pos;
bool SelectOurPosition(unsigned long){return pos.open;}
int SideFromPositionType(long t){return t==POSITION_TYPE_BUY ? 1 : -1;}
long PositionGetInteger(int p){return p==POSITION_TIME ? pos.time : pos.side;}
double PositionGetDouble(int p){return p==POSITION_PRICE_OPEN ? pos.entry : p==POSITION_SL ? pos.sl : pos.vol;}
string PositionGetString(int){return "TEST";}
string StringFormat(const char*,double){return "reason";}
long SymbolInfoInteger(string,int){return 10;}
double NormalizePriceToTick(double price,int){return price;}
int pending=0;
int OrdersTotal(){return pending;}
int PositionsTotal(){return pos.open?1:0;}
unsigned long PositionGetTicket(int){return pos.open?1:0;}
bool PositionSelectByTicket(unsigned long){return pos.open;}
MqlTick quote={100.0,100.2};
bool SymbolInfoTick(string,MqlTick &t){t=quote;return true;}
bool OrderCalcProfit(ENUM_ORDER_TYPE side,string,double vol,double from,double to,double &out)
 {out=(side==ORDER_TYPE_BUY ? 1 : -1)*(to-from)*vol;return true;}
double AccountInfoDouble(int){return 100;}
string g_last_action;
'''
test = r'''
int main(){
 vector<MqlRates> rates;
 for(int i=0;i<10;i++) rates.push_back({101,99,100,i,SQZ_STATE_NONE});
 vector<double> v(10,0.0); vector<int> valid(10,1);
 vector<ENUM_SQZ_BAR_COLOR> c(10,SQZ_COLOR_GREEN);
 assert(LabATR(rates,1)==0 && fabs(LabATR(rates,2)-2)<1e-9);
 assert(LabSignalWeight(rates,v,4)==1.0);
 InpWeightedSignals=true; v[4]=0.2;
 assert(fabs(LabSignalWeight(rates,v,4)-1)<1e-9);
 v[4]=10; assert(LabSignalWeight(rates,v,4)==2.0);
 v[4]=0; assert(LabSignalWeight(rates,v,4)==0.25);
 InpWeightedSignals=false;
 c[3]=SQZ_COLOR_RED;c[4]=SQZ_COLOR_MAROON;
 assert(LabEntrySignal(rates,v,c,valid,4)==1);
 InpLabEntryMode=LAB_SQUEEZE_REVERSAL;
 rates[2].state=SQZ_STATE_ON; rates[3].state=SQZ_STATE_NONE; rates[4].state=SQZ_STATE_OFF;
 assert(LabEntrySignal(rates,v,c,valid,4)==1);
 rates[3].state=SQZ_STATE_OFF; assert(LabEntrySignal(rates,v,c,valid,4)==0);
 rates[3].state=SQZ_STATE_NONE; InpLabEntryMode=LAB_SQUEEZE_TREND; v[4]=-1;
 assert(LabEntrySignal(rates,v,c,valid,4)==-1);
 c.assign(10,SQZ_COLOR_GREEN); c[3]=SQZ_COLOR_RED; c[4]=SQZ_COLOR_MAROON;
 c[6]=SQZ_COLOR_RED; c[7]=SQZ_COLOR_MAROON; rates[4].close=101;rates[7].close=101;
 pos={true,POSITION_TYPE_BUY,100,99,1,3}; string reason; double tp=0,sl=0;
 assert(EvaluatePositionExit(1,rates,v,c,valid,reason,tp,sl)==1 && tp==2);
 pos.time=4; InpTakeProfitSignalCount=1; // closing at the entry boundary is not counted
 c[6]=SQZ_COLOR_GREEN; c[7]=SQZ_COLOR_GREEN;
 assert(EvaluatePositionExit(1,rates,v,c,valid,reason,tp,sl)==1); // signal closed at time 5, after entry
 pos.time=5; assert(EvaluatePositionExit(1,rates,v,c,valid,reason,tp,sl)==0);
 pos.time=1; assert(EvaluatePositionExit(1,rates,v,c,valid,reason,tp,sl)==-2); // missing warmup
 MqlTick t={100,100.2}; double stop=0,take=0;
 InpFixedStopLossPoints=10; assert(!BuildFixedExits(1,100.2,t,stop,take));
 InpFixedStopLossPoints=50; assert(BuildFixedExits(1,100.2,t,stop,take));
 InpRiskBudgetPercent=1; pos={true,POSITION_TYPE_BUY,100,99,1,3};
 assert(!LabRiskBudgetOK(1,1,100.2,99)); // account risk exceeds 1%
 InpRiskBudgetPercent=3; assert(LabRiskBudgetOK(1,1,100.2,99));
 pos.sl=0; assert(!LabRiskBudgetOK(1,1,100.2,99)); // missing SL
 pos.open=false; pending=1; assert(!LabRiskBudgetOK(1,1,100.2,99));
 pending=0; assert(!LabRiskBudgetOK(1,1,100.2,0)); // missing new SL
 puts("Lab calculation/risk smoke tests passed");
}
'''
with tempfile.TemporaryDirectory() as d:
    cpp = Path(d) / 'test.cpp'
    binary = Path(d) / 'test'
    cpp.write_text(pre + code + test)
    subprocess.run(['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror', str(cpp), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
