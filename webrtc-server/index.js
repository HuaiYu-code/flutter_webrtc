const WebSocket = require('ws');

// 创建 WebSocket 服务器，监听端口 8080
const wss = new WebSocket.Server({ port: 8080 });

// 存储连接的客户端
let clients = {};

// 当有新的连接建立时
wss.on('connection', function connection(ws) {
  console.log('New client connected');

  // 为每个连接的客户端分配一个随机 ID
  const clientId = Math.random().toString(36).substring(7);
  clients[clientId] = ws;

  // 发送分配的客户端 ID 给客户端
  ws.send(JSON.stringify({ type: 'client-id', id: clientId }));

  // 当收到消息时
  ws.on('message', function incoming(message) {
    // 解析收到的消息
    const data = JSON.parse(message);
    console.log('Received message:', data);

    // 根据消息类型处理
    switch (data.type) {
      case 'offer':
        // 将 offer 转发给目标客户端
        if (clients[data.target]) {
          clients[data.target].send(JSON.stringify({
            type: 'offer',
            offer: data.offer,
            sender: data.sender
          }));
        }
        break;
      case 'answer':
        // 将 answer 转发给目标客户端
        if (clients[data.target]) {
          clients[data.target].send(JSON.stringify({
            type: 'answer',
            answer: data.answer,
            sender: data.sender
          }));
        }
        break;
      case 'ice_candidate':
        // 将 ICE candidate 转发给目标客户端
        if (clients[data.target]) {
          clients[data.target].send(JSON.stringify({
            type: 'ice_candidate',
            candidate: data.candidate,
            sender: data.sender
          }));
        }
        break;
      default:
        console.log('Unknown message type:', data.type);
        break;
    }
  });

  // 当连接关闭时
  ws.on('close', function close() {
    console.log('Client disconnected');
    // 删除断开连接的客户端
    delete clients[clientId];
  });
});
