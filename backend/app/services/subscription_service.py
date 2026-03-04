import base64
import json
import yaml
from typing import Optional
from sqlalchemy.orm import Session
from app.db.models import Subscription
from app.core.config import settings


class SubscriptionService:
    def __init__(self, db: Session):
        self.db = db

    def get_subscription_by_token(self, token: str) -> Optional[Subscription]:
        return self.db.query(Subscription).filter(
            Subscription.token == token,
            Subscription.is_active == True
        ).first()

    def build_base64_subscription(self, subscription: Subscription) -> str:
        nodes = self._get_server_nodes()
        links = []

        for node in nodes:
            if node["protocol"] == "vmess":
                vmess_config = {
                    "v": "2",
                    "ps": node["name"],
                    "add": node["address"],
                    "port": str(node["port"]),
                    "id": node["uuid"],
                    "aid": "0",
                    "net": node.get("network", "tcp"),
                    "type": node.get("type", "none"),
                    "host": node.get("host", ""),
                    "path": node.get("path", ""),
                    "tls": node.get("tls", ""),
                    "sni": node.get("sni", ""),
                }
                vmess_json = json.dumps(vmess_config, separators=(',', ':'))
                vmess_b64 = base64.b64encode(vmess_json.encode()).decode()
                links.append(f"vmess://{vmess_b64}")
            elif node["protocol"] == "vless":
                params = []
                if node.get("type"):
                    params.append(f"type={node['type']}")
                if node.get("security"):
                    params.append(f"security={node['security']}")
                if node.get("sni"):
                    params.append(f"sni={node['sni']}")
                if node.get("flow"):
                    params.append(f"flow={node['flow']}")

                param_str = "&".join(params) if params else ""
                vless_link = f"vless://{node['uuid']}@{node['address']}:{node['port']}"
                if param_str:
                    vless_link += f"?{param_str}"
                vless_link += f"#{node['name']}"
                links.append(vless_link)

        content = "\n".join(links)
        return base64.b64encode(content.encode()).decode()

    def build_clash_subscription(self, subscription: Subscription) -> str:
        nodes = self._get_server_nodes()
        proxies = []
        proxy_names = []

        for node in nodes:
            proxy_names.append(node["name"])

            if node["protocol"] == "vmess":
                proxy = {
                    "name": node["name"],
                    "type": "vmess",
                    "server": node["address"],
                    "port": node["port"],
                    "uuid": node["uuid"],
                    "alterId": 0,
                    "cipher": "auto",
                    "network": node.get("network", "tcp"),
                }
                if node.get("tls"):
                    proxy["tls"] = True
                    if node.get("sni"):
                        proxy["servername"] = node["sni"]
                if node.get("network") == "ws":
                    proxy["ws-opts"] = {
                        "path": node.get("path", "/"),
                        "headers": {"Host": node.get("host", "")} if node.get("host") else {}
                    }
                proxies.append(proxy)
            elif node["protocol"] == "vless":
                proxy = {
                    "name": node["name"],
                    "type": "vless",
                    "server": node["address"],
                    "port": node["port"],
                    "uuid": node["uuid"],
                    "network": node.get("network", "tcp"),
                }
                if node.get("tls"):
                    proxy["tls"] = True
                    if node.get("sni"):
                        proxy["servername"] = node["sni"]
                if node.get("flow"):
                    proxy["flow"] = node["flow"]
                proxies.append(proxy)

        clash_config = {
            "proxies": proxies,
            "proxy-groups": [
                {
                    "name": "PROXY",
                    "type": "select",
                    "proxies": proxy_names
                },
                {
                    "name": "AUTO",
                    "type": "url-test",
                    "proxies": proxy_names,
                    "url": "http://www.gstatic.com/generate_204",
                    "interval": 300
                }
            ]
        }

        return yaml.dump(clash_config, allow_unicode=True, default_flow_style=False)

    def build_singbox_subscription(self, subscription: Subscription) -> str:
        nodes = self._get_server_nodes()
        outbounds = []

        for node in nodes:
            if node["protocol"] == "vmess":
                outbound = {
                    "type": "vmess",
                    "tag": node["name"],
                    "server": node["address"],
                    "server_port": node["port"],
                    "uuid": node["uuid"],
                    "security": "auto",
                    "alter_id": 0,
                }
                if node.get("network") == "ws":
                    outbound["transport"] = {
                        "type": "ws",
                        "path": node.get("path", "/"),
                        "headers": {"Host": node.get("host", "")} if node.get("host") else {}
                    }
                if node.get("tls"):
                    outbound["tls"] = {
                        "enabled": True,
                        "server_name": node.get("sni", "")
                    }
                outbounds.append(outbound)
            elif node["protocol"] == "vless":
                outbound = {
                    "type": "vless",
                    "tag": node["name"],
                    "server": node["address"],
                    "server_port": node["port"],
                    "uuid": node["uuid"],
                }
                if node.get("flow"):
                    outbound["flow"] = node["flow"]
                if node.get("tls"):
                    outbound["tls"] = {
                        "enabled": True,
                        "server_name": node.get("sni", "")
                    }
                outbounds.append(outbound)

        singbox_config = {
            "outbounds": outbounds
        }

        return json.dumps(singbox_config, indent=2, ensure_ascii=False)

    def _get_server_nodes(self) -> list[dict]:
        server_config = getattr(settings, "SERVER_NODES", None)
        if server_config:
            return server_config

        return [
            {
                "name": "Default Node",
                "protocol": "vmess",
                "address": "example.com",
                "port": 443,
                "uuid": "00000000-0000-0000-0000-000000000000",
                "network": "ws",
                "path": "/",
                "tls": "tls",
                "sni": "example.com"
            }
        ]
