"""
3x-ui API 客户端
用于与3x-ui面板进行交互，获取流量数据和管理用户
"""
import httpx
from typing import Optional, Dict, Any, List
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class XUIClient:
    """3x-ui API 客户端"""

    def __init__(self, base_url: str, username: str, password: str):
        """
        初始化3x-ui客户端

        Args:
            base_url: 3x-ui面板地址，如 http://localhost:2053
            username: 登录用户名
            password: 登录密码
        """
        self.base_url = base_url.rstrip('/')
        self.username = username
        self.password = password
        self.session_cookie: Optional[str] = None
        self.client = httpx.Client(timeout=30.0)

    def login(self) -> bool:
        """
        登录3x-ui面板获取session

        Returns:
            bool: 登录是否成功
        """
        try:
            response = self.client.post(
                f"{self.base_url}/login",
                data={
                    "username": self.username,
                    "password": self.password
                }
            )

            if response.status_code == 200:
                # 获取session cookie
                cookies = response.cookies
                if "session" in cookies or "3x-ui" in cookies:
                    self.session_cookie = response.cookies
                    logger.info("3x-ui登录成功")
                    return True

            logger.error(f"3x-ui登录失败: {response.status_code}")
            return False

        except Exception as e:
            logger.error(f"3x-ui登录异常: {e}")
            return False

    def _ensure_login(self):
        """确保已登录，如果未登录则自动登录"""
        if not self.session_cookie:
            if not self.login():
                raise Exception("无法登录3x-ui")

    def _request(self, method: str, path: str, **kwargs) -> Dict[str, Any]:
        """
        发送HTTP请求

        Args:
            method: HTTP方法
            path: API路径
            **kwargs: 其他请求参数

        Returns:
            响应JSON数据
        """
        self._ensure_login()

        url = f"{self.base_url}{path}"
        response = self.client.request(
            method,
            url,
            cookies=self.session_cookie,
            **kwargs
        )

        if response.status_code == 200:
            return response.json()
        else:
            raise Exception(f"请求失败: {response.status_code} - {response.text}")

    def get_inbounds(self) -> List[Dict[str, Any]]:
        """
        获取所有inbound列表

        Returns:
            inbound列表
        """
        result = self._request("GET", "/panel/api/inbounds/list")
        return result.get("obj", [])

    def get_inbound(self, inbound_id: int) -> Dict[str, Any]:
        """
        获取单个inbound信息

        Args:
            inbound_id: inbound ID

        Returns:
            inbound信息
        """
        result = self._request("GET", f"/panel/api/inbounds/get/{inbound_id}")
        return result.get("obj", {})

    def add_client(
        self,
        inbound_id: int,
        email: str,
        uuid: str,
        enable: bool = True,
        flow: str = "",
        limit_ip: int = 0,
        total_gb: int = 0,
        expire_time: int = 0,
        telegram_id: str = "",
        subscription_id: str = ""
    ) -> bool:
        """
        添加客户端到指定inbound

        Args:
            inbound_id: inbound ID
            email: 客户端邮箱（唯一标识）
            uuid: 客户端UUID
            enable: 是否启用
            flow: 流控模式
            limit_ip: IP限制数量
            total_gb: 总流量限制（GB）
            expire_time: 过期时间（Unix时间戳，毫秒）
            telegram_id: Telegram ID
            subscription_id: 订阅ID

        Returns:
            是否成功
        """
        data = {
            "id": inbound_id,
            "settings": {
                "clients": [{
                    "id": uuid,
                    "email": email,
                    "enable": enable,
                    "flow": flow,
                    "limitIp": limit_ip,
                    "totalGB": total_gb * 1024 * 1024 * 1024 if total_gb > 0 else 0,
                    "expiryTime": expire_time,
                    "tgId": telegram_id,
                    "subId": subscription_id
                }]
            }
        }

        try:
            self._request("POST", "/panel/api/inbounds/addClient", json=data)
            logger.info(f"成功添加客户端: {email}")
            return True
        except Exception as e:
            logger.error(f"添加客户端失败: {e}")
            return False

    def delete_client(self, inbound_id: int, client_id: str) -> bool:
        """
        删除客户端

        Args:
            inbound_id: inbound ID
            client_id: 客户端UUID

        Returns:
            是否成功
        """
        try:
            self._request("POST", f"/panel/api/inbounds/{inbound_id}/delClient/{client_id}")
            logger.info(f"成功删除客户端: {client_id}")
            return True
        except Exception as e:
            logger.error(f"删除客户端失败: {e}")
            return False

    def get_client_traffic(self, email: str) -> Dict[str, Any]:
        """
        获取客户端流量信息

        Args:
            email: 客户端邮箱

        Returns:
            流量信息 {
                "up": 上传字节数,
                "down": 下载字节数,
                "total": 总字节数,
                "enable": 是否启用,
                "expiryTime": 过期时间
            }
        """
        result = self._request("GET", f"/panel/api/inbounds/getClientTraffics/{email}")
        obj = result.get("obj", {})

        if obj:
            return {
                "up": obj.get("up", 0),
                "down": obj.get("down", 0),
                "total": obj.get("up", 0) + obj.get("down", 0),
                "enable": obj.get("enable", False),
                "expiryTime": obj.get("expiryTime", 0)
            }

        return {
            "up": 0,
            "down": 0,
            "total": 0,
            "enable": False,
            "expiryTime": 0
        }

    def get_client_traffic_by_id(self, inbound_id: int) -> List[Dict[str, Any]]:
        """
        获取指定inbound下所有客户端的流量信息

        Args:
            inbound_id: inbound ID

        Returns:
            客户端流量列表
        """
        result = self._request("GET", f"/panel/api/inbounds/getClientTrafficsById/{inbound_id}")
        return result.get("obj", [])

    def reset_client_traffic(self, inbound_id: int, email: str) -> bool:
        """
        重置客户端流量

        Args:
            inbound_id: inbound ID
            email: 客户端邮箱

        Returns:
            是否成功
        """
        try:
            self._request("POST", f"/panel/api/inbounds/{inbound_id}/resetClientTraffic/{email}")
            logger.info(f"成功重置客户端流量: {email}")
            return True
        except Exception as e:
            logger.error(f"重置客户端流量失败: {e}")
            return False

    def get_server_status(self) -> Dict[str, Any]:
        """
        获取服务器状态

        Returns:
            服务器状态信息 {
                "cpu": CPU使用率,
                "mem": 内存信息,
                "disk": 磁盘信息,
                "xray": Xray状态,
                "uptime": 运行时间,
                "loads": 负载
            }
        """
        result = self._request("POST", "/panel/api/server/status")
        return result.get("obj", {})

    def get_online_clients(self) -> List[str]:
        """
        获取在线客户端列表

        Returns:
            在线客户端邮箱列表
        """
        result = self._request("POST", "/panel/api/inbounds/onlines")
        return result.get("obj", [])

    def close(self):
        """关闭HTTP客户端"""
        self.client.close()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()
