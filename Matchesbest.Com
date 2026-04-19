<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Matches Predictor FIXED</title>

<style>
body{background:#0B0F1A;color:white;font-family:sans-serif;padding:15px;margin:0}
.header{color:#00D9FF;font-size:24px;font-weight:bold;margin-bottom:20px}

.card{
  background:#151A2A;
  border:1px solid #1F2535;
  border-radius:16px;
  padding:25px 20px;
  margin-bottom:20px;
  text-align:center
}

.card-title{
  color:#00D9FF;
  font-size:18px;
  font-weight:600;
  margin-bottom:20px
}

.circle{
  width:110px;
  height:110px;
  border-radius:50%;
  margin:0 auto 12px auto;
  display:flex;
  align-items:center;
  justify-content:center;
  font-size:42px;
  font-weight:bold
}

.countdown{background:#1A2030;color:#FFF}
.blue{background:linear-gradient(135deg,#00A8FF,#0077FF)}

.confidence{
  color:#FFC107;
  font-size:16px;
  font-weight:600;
  margin-bottom:4px;
}

.entry{
  color:#00D9FF;
  font-size:16px;
  font-weight:600;
}
</style>
</head>

<body>

<div class="header">Matches Predictor (Balanced)</div>
<div id="container"></div>

<script>
window.onload = function() {

  const markets = [
    {symbol:"R_10", name:"Volatility 10 (1s)"},
    {symbol:"R_25", name:"Volatility 25 (1s)"},
    {symbol:"R_50", name:"Volatility 50 (1s)"},
    {symbol:"R_75", name:"Volatility 75 (1s)"},
    {symbol:"R_100", name:"Volatility 100 (1s)"}
  ];

  const container = document.getElementById("container");
  let data = {};

  markets.forEach((m, index) => {

    data[m.symbol] = {
      digits:{0:0,1:0,2:0,3:0,4:0,5:0,6:0,7:0,8:0,9:0},
      total:0,
      phase:1,
      timer:10
    };

    let div = document.createElement("div");
    div.className = "card";
    div.innerHTML = `
      <div class="card-title">${m.name}</div>
      <div class="circle countdown" id="${m.symbol}_circle">10s</div>
      <div class="confidence" id="${m.symbol}_conf">Collecting...</div>
      <div class="entry" id="${m.symbol}_entry"></div>
    `;
    container.appendChild(div);

    setInterval(()=>{
      let d = data[m.symbol];
      let circle = document.getElementById(m.symbol+"_circle");
      let conf = document.getElementById(m.symbol+"_conf");
      let entry = document.getElementById(m.symbol+"_entry");

      d.timer--;

      if(d.phase === 1){

        circle.innerText = d.timer+'s';
        entry.innerText = "Analyzing...";

        if(d.timer <= 0){

          let maxCount=0, maxDigit=0;

          for(let i=0;i<=9;i++){
            if(d.digits[i] > maxCount){
              maxCount = d.digits[i];
              maxDigit = i;
            }
          }

          let confidence = d.total > 0
            ? Math.round((maxCount / d.total) * 100)
            : 0;

          // NEW BALANCED SIGNAL
          let signal = "";
          if(confidence >= 70){
            signal = "🔥 BEST";
          }else if(confidence >= 50){
            signal = "👍 GOOD";
          }else{
            signal = "⚠️ WEAK";
          }

          d.phase = 2;
          d.timer = 5;

          circle.className = "circle blue";
          circle.innerText = maxDigit;

          conf.innerText = `${signal} (${confidence}%)`;
          entry.innerText = `Entry in ${d.timer}s`;

          d.digits = {0:0,1:0,2:0,3:0,4:0,5:0,6:0,7:0,8:0,9:0};
          d.total = 0;
        }

      } else {

        entry.innerText = `Entry in ${d.timer}s`;

        if(d.timer <= 0){
          d.phase = 1;
          d.timer = 10;
          circle.className = 'circle countdown';
          circle.innerText = d.timer+'s';
          conf.innerText = 'Collecting...';
          entry.innerText = '';
        }
      }

    },1000);

    setTimeout(() => {

      let ws = new WebSocket('wss://ws.derivws.com/websockets/v3?app_id=1089');

      ws.onopen = () => {
        ws.send(JSON.stringify({ticks:m.symbol, subscribe:1}));
      };

      ws.onmessage = e => {
        let res = JSON.parse(e.data);

        if(res.tick && data[m.symbol].phase === 1){

          let last = parseInt(res.tick.quote.toString().slice(-1));

          // simple + stable (NO decay issues)
          data[m.symbol].digits[last]++;
          data[m.symbol].total++;
        }
      };

    }, index * 500);

  });

};
</script>

</body>
</html>
