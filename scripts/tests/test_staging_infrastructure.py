from pathlib import Path


ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_staging_stack_has_required_isolation_and_resources() -> None:
    template = read("infra/aws-staging.yaml")
    for marker in (
        "AWS::ECR::Repository",
        "AWS::S3::Bucket",
        "AWS::SSM::Parameter",
        "AWS::IAM::OIDCProvider",
        "AWS::EC2::Instance",
        "InstanceType: t3.medium",
        "BlockPublicAcls: true",
        "Encrypted: true",
        "FromPort: 80",
        "FromPort: 443",
    ):
        assert marker in template
    assert "FromPort: 22" not in template


def test_deploy_workflow_uses_oidc_and_serial_deploys() -> None:
    workflow = read(".github/workflows/deploy-staging.yml")
    assert "id-token: write" in workflow
    assert "configure-aws-credentials" in workflow
    assert "concurrency:" in workflow
    assert "cancel-in-progress: false" in workflow
    assert "health/ready" in workflow
    assert "gh issue create" in workflow


def test_runtime_scripts_do_not_contain_real_credentials() -> None:
    for path in ("infra/backup.sh", "infra/remote-deploy.sh", "infra/rollback.sh"):
        content = read(path)
        assert "CHANGE_ME" not in content
        assert "AKIA" not in content
        assert "ghp_" not in content
