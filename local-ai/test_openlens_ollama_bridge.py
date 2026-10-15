import json
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from openlens_ollama_bridge import OpenLensBridge, instructions


class LocalModelBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.requests = []

        def fake_ollama(path, payload, timeout):
            if path == "/api/tags":
                return {"models": [{"name": "qwen3:4b-instruct"}]}
            if path == "/api/chat":
                cls.requests.append(payload)
                return {"message": {"content": "Hello, this is a local answer."}}
            raise AssertionError(f"Unexpected Ollama request {path}")

        cls.server = OpenLensBridge(("127.0.0.1", 0), "a" * 48, "qwen3:4b-instruct",
                                    transport=fake_ollama)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join(timeout=2)

    def request(self, path, payload=None, *, token="a" * 48, method="GET"):
        headers = {"Authorization": f"Bearer {token}"}
        data = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(payload).encode()
        req = Request(f"http://127.0.0.1:{self.port}{path}",
                      data=data, headers=headers, method=method)
        try:
            with urlopen(req, timeout=3) as response:
                return response.status, json.loads(response.read())
        except HTTPError as exc:
            return exc.code, json.loads(exc.read())

    def test_requires_pairing_token(self):
        status, _ = self.request("/openlens/health", token="wrong-token")
        self.assertEqual(status, 401)
        status, _ = self.request("/openlens", {"mode": "ai", "text": "hello"}, token="no")
        self.assertEqual(status, 401)

    def test_health_checks_installed_ollama_model(self):
        status, payload = self.request("/openlens/health")
        self.assertEqual(status, 200)
        self.assertTrue(payload["configured"])
        self.assertEqual(payload["service"], "openlens-local")
        self.assertTrue(payload["offline"])

    def test_generate_answer_only_via_local_ollama(self):
        status, payload = self.request("/openlens", {
            "mode": "ai", "task": "explain", "text": "What is photosynthesis?"
        }, method="POST")
        self.assertEqual(status, 200)
        self.assertEqual(payload["text"], "Hello, this is a local answer.")
        recent = self.requests[-1]
        self.assertEqual(recent["model"], "qwen3:4b-instruct")
        self.assertEqual(recent["stream"], False)
        self.assertEqual(recent["messages"][1]["content"], "What is photosynthesis?")
        self.assertIn("Explain", recent["messages"][0]["content"])

    def test_translate_without_cloud(self):
        status, _ = self.request("/openlens", {
            "mode": "translate", "text": "Hello", "target_language": "hi"
        }, method="POST")
        self.assertEqual(status, 200)
        self.assertIn("Hindi", self.requests[-1]["messages"][0]["content"])

    def test_rejects_invalid_requests(self):
        invalid = [
            {"mode": "wrong", "text": "hello"},
            {"mode": "ai", "text": ""},
            {"mode": "ai", "task": "unsafe-mode", "text": "hello"},
            {"mode": "translate", "text": "Hello", "target_language": "bad"},
            {"mode": "ai", "text": "x" * 3001},
        ]
        for payload in invalid:
            with self.subTest(payload=str(payload)[:30]):
                status, _ = self.request("/openlens", payload, method="POST")
                self.assertEqual(status, 400)

    def test_bridge_never_calls_cloud_or_needs_openai_key(self):
        status, body = self.request("/openlens/health")
        self.assertEqual(status, 200)
        self.assertNotIn("api_key", body)
        self.assertNotIn("OpenAI", json.dumps(body))


class PromptTests(unittest.TestCase):
    def test_all_ai_actions(self):
        for action in ["general", "explain", "summarize", "rewrite", "brainstorm"]:
            self.assertGreater(len(instructions("ai", action, "en")), 30)

    def test_translations_preserve_names(self):
        for code in ["en", "es", "fr", "hi", "te"]:
            msg = instructions("translate", "general", code)
            self.assertIn("street names", msg)
            self.assertIn("Return only the translation", msg)


if __name__ == "__main__":
    unittest.main()
