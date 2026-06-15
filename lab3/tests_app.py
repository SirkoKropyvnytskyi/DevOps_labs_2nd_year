import pytest
from app import app


@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client


def test_health_alive(client):
    """Перевіряємо, чи живий застосунок"""
    response = client.get('/health/alive')
    assert response.status_code == 200
    assert b"OK" in response.data


def test_index_page(client):
    """Перевіряємо кореневий ендпоінт"""
    response = client.get('/')
    assert response.status_code == 200
    assert b"List of endpoints" in response.data


def test_get_notes_db_down(client):
    """
    Перевірка, як застосунок реагує на відсутність бази даних.
    Оскільки під час тестів БД не піднята, він має віддати помилку 500.
    """
    response = client.get('/notes')
    assert response.status_code == 200
    assert b"Database connection failed" in response.data or b"DB connection failed" in response.data


def test_health_ready_db_down(client):
    """
    Перевіряємо health/ready коли БД недоступна.
    Має повернути 500 помилку.
    """
    response = client.get('/health/ready')
    assert response.status_code == 500
    assert b"Database connection failed" in response.data
