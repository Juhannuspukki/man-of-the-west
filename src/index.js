// JS Goes here - ES6 supported

import "./css/main.scss";

function startTime() {
  const d = new Date();
  
  const utc = d.getTime() + (d.getTimezoneOffset() * 60000);
  
  const nd = new Date(utc + (3600000*7));
  
  document.getElementById('clock').innerHTML = "" + nd.toLocaleString();
  
  setTimeout(startTime, 500);
}
window.addEventListener('load', function() {
  startTime()
})

// Say hello
console.log("🦊 Hello! Edit me in src/index.js");
