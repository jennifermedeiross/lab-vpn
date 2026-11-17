#!/usr/bin/env bash
set -euo pipefail

CLIENTE=vpn-cliente
GATEWAY=vpn-gateway
DIR=/tmp/laboratorio-vpn-ubuntu

limpar() {
  if [[ -f "$DIR/servidor.pid" ]]; then
    kill "$(cat "$DIR/servidor.pid")" 2>/dev/null || true
  fi
  ip netns del "$CLIENTE" 2>/dev/null || true
  ip netns del "$GATEWAY" 2>/dev/null || true
  rm -rf "$DIR"
  echo 'Laboratorio removido.'
}

if [[ $EUID -ne 0 ]]; then
  echo 'Execute com sudo: sudo bash laboratorio_vpn_ubuntu.sh iniciar|ativar|limpar'
  exit 1
fi

case "${1:-}" in
  iniciar)
    command -v wg >/dev/null || { echo 'Instale wireguard-tools.'; exit 1; }
    command -v ip >/dev/null || { echo 'Instale iproute2.'; exit 1; }
    limpar >/dev/null
    umask 077
    mkdir -p "$DIR/www"
    echo 'Servidor interno acessado pela VPN!' > "$DIR/www/index.html"
    wg genkey > "$DIR/cliente.key"
    wg pubkey < "$DIR/cliente.key" > "$DIR/cliente.pub"
    wg genkey > "$DIR/gateway.key"
    wg pubkey < "$DIR/gateway.key" > "$DIR/gateway.pub"

    ip netns add "$CLIENTE"
    ip netns add "$GATEWAY"
    ip link add veth-casa type veth peer name veth-vpn
    ip link set veth-casa netns "$CLIENTE"
    ip link set veth-vpn netns "$GATEWAY"
    ip -n "$CLIENTE" link set lo up
    ip -n "$GATEWAY" link set lo up
    ip -n "$CLIENTE" addr add 198.51.100.2/24 dev veth-casa
    ip -n "$GATEWAY" addr add 198.51.100.1/24 dev veth-vpn
    ip -n "$CLIENTE" link set veth-casa up
    ip -n "$GATEWAY" link set veth-vpn up

    ip -n "$GATEWAY" addr add 10.0.0.10/32 dev lo
    ip netns exec "$GATEWAY" python3 -m http.server 8000 --bind 10.0.0.10 --directory "$DIR/www" > "$DIR/servidor.log" 2>&1 &
    echo $! > "$DIR/servidor.pid"

    ip -n "$CLIENTE" link add wg0 type wireguard
    ip -n "$GATEWAY" link add wg0 type wireguard
    ip -n "$CLIENTE" addr add 10.8.0.2/32 dev wg0
    ip -n "$GATEWAY" addr add 10.8.0.1/32 dev wg0
    ip netns exec "$GATEWAY" wg set wg0 private-key "$DIR/gateway.key" listen-port 51820 peer "$(cat "$DIR/cliente.pub")" allowed-ips 10.8.0.2/32
    ip netns exec "$CLIENTE" wg set wg0 private-key "$DIR/cliente.key" peer "$(cat "$DIR/gateway.pub")" allowed-ips 10.0.0.10/32 endpoint 198.51.100.1:51820
    ip -n "$GATEWAY" link set wg0 up
    ip -n "$GATEWAY" route add 10.8.0.2/32 dev wg0

    echo 'Ambiente pronto, VPN do cliente ainda desligada.'
    echo 'ANTES: sudo ip netns exec vpn-cliente ip route get 10.0.0.10'
    echo 'ANTES: sudo ip netns exec vpn-cliente curl -m 4 -v http://10.0.0.10:8000'
    echo 'Para ativar: sudo bash laboratorio_vpn_ubuntu.sh ativar'
    ;;
  ativar)
    ip -n "$CLIENTE" link set wg0 up
    ip -n "$CLIENTE" route replace 10.0.0.10/32 dev wg0
    echo 'VPN do cliente ativada.'
    echo 'DEPOIS: sudo ip netns exec vpn-cliente ip route get 10.0.0.10'
    echo 'DEPOIS: sudo ip netns exec vpn-cliente curl -m 5 http://10.0.0.10:8000'
    ;;
  limpar)
    limpar
    ;;
  *)
    echo 'Uso: sudo bash laboratorio_vpn_ubuntu.sh iniciar|ativar|limpar'
    exit 1
    ;;
esac
